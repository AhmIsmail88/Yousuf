"""تحويل نموذج Whisper قرآني (Hugging Face) إلى صيغة ggml لـ whisper.cpp.

    python tools/asr/convert_to_ggml.py <hf_model_dir> <mel_filters.npz> <out.bin>

النموذج المعتمد: tarteel-ai/whisper-base-ar-quran (Apache-2.0) — Whisper base
مُدرَّب على تلاوة القرآن. الملف الناتج (f16، ~١٤٨ م.ب) يُنزَّل في التطبيق
عند أول استخدام لوضع التسميع، ويعمل على الجهاز بلا إنترنت.

صيغة الملف (مطابقة لما يقرؤه whisper.cpp):
  magic 'ggml' · hparams (11 × int32) · مرشحات mel · المفردات · الأوزان.
الأوزان الصغيرة (أحادية البعد والتحيّزات والمواضع) float32، والباقي float16.
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import numpy as np
import torch
from transformers import WhisperForConditionalGeneration

# أسماء طبقات Hugging Face ← أسماء whisper.cpp
CONV_MAP = {
    "self_attn.k_proj": "attn.key",
    "self_attn.q_proj": "attn.query",
    "self_attn.v_proj": "attn.value",
    "self_attn.out_proj": "attn.out",
    "self_attn_layer_norm": "attn_ln",
    "encoder_attn.q_proj": "cross_attn.query",
    "encoder_attn.v_proj": "cross_attn.value",
    "encoder_attn.out_proj": "cross_attn.out",
    "encoder_attn_layer_norm": "cross_attn_ln",
    "fc1": "mlp.0",
    "fc2": "mlp.2",
    "final_layer_norm": "mlp_ln",
    "encoder.layer_norm.bias": "encoder.ln_post.bias",
    "encoder.layer_norm.weight": "encoder.ln_post.weight",
    "encoder.embed_positions.weight": "encoder.positional_embedding",
    "decoder.layer_norm.bias": "decoder.ln.bias",
    "decoder.layer_norm.weight": "decoder.ln.weight",
    "decoder.embed_positions.weight": "decoder.positional_embedding",
    "decoder.embed_tokens.weight": "decoder.token_embedding.weight",
}

F32_NAMES = {
    "encoder.conv1.bias",
    "encoder.conv2.bias",
    "encoder.positional_embedding",
    "decoder.positional_embedding",
}


def bytes_to_unicode() -> dict[int, str]:
    """جدول GPT-2 لتحويل البايتات إلى محارف قابلة للعرض (معكوسه يعيد البايتات)."""
    bs = (
        list(range(ord("!"), ord("~") + 1))
        + list(range(ord("¡"), ord("¬") + 1))
        + list(range(ord("®"), ord("ÿ") + 1))
    )
    cs = bs[:]
    n = 0
    for b in range(256):
        if b not in bs:
            bs.append(b)
            cs.append(256 + n)
            n += 1
    return dict(zip(bs, [chr(c) for c in cs]))


def ggml_name(hf_name: str) -> str:
    parts = hf_name.split(".")[1:]  # إسقاط البادئة model.
    if parts[1] == "layers":
        parts[1] = "blocks"
        inner = ".".join(parts[3:-1])
        if inner == "encoder_attn.k_proj":
            mapped = "attn.key" if parts[0] == "encoder" else "cross_attn.key"
        else:
            mapped = CONV_MAP[inner]
        return ".".join(parts[:3] + [mapped] + parts[-1:])
    name = ".".join(parts)
    return CONV_MAP.get(name, name)


def convert(model_dir: Path, mel_npz: Path, out: Path) -> None:
    vocab = json.loads((model_dir / "vocab.json").read_text(encoding="utf-8"))
    hp = json.loads((model_dir / "config.json").read_text(encoding="utf-8"))
    # n_text_ctx = طول سياق النص (decoder.positional_embedding = 448).
    # لا يؤخذ من max_length: ذاك حدّ للتوليد (1024 في نموذج Tarteel)، ولو
    # كُتب في الرأس لرفض whisper.cpp الملف ("failed to load model").
    max_length = hp.get("max_target_positions", 448)
    model = WhisperForConditionalGeneration.from_pretrained(model_dir)

    n_mels = hp["num_mel_bins"]
    with np.load(mel_npz, allow_pickle=False) as f:
        filters = f[f"mel_{n_mels}"].astype(np.float32)

    with out.open("wb") as fout:
        fout.write(struct.pack("i", 0x67676D6C))  # 'ggml'
        for value in (
            hp["vocab_size"],
            hp["max_source_positions"],
            hp["d_model"],
            hp["encoder_attention_heads"],
            hp["encoder_layers"],
            int(max_length),
            hp["d_model"],
            hp["decoder_attention_heads"],
            hp["decoder_layers"],
            n_mels,
            1,  # f16
        ):
            fout.write(struct.pack("i", value))

        fout.write(struct.pack("ii", *filters.shape))
        fout.write(filters.tobytes())

        byte_decoder = {v: k for k, v in bytes_to_unicode().items()}
        fout.write(struct.pack("i", len(vocab)))
        for token, _ in sorted(vocab.items(), key=lambda item: item[1]):
            raw = bytes(byte_decoder[c] for c in token)
            fout.write(struct.pack("i", len(raw)))
            fout.write(raw)

        for hf_name, tensor in model.state_dict().items():
            if hf_name == "proj_out.weight":  # مربوط بتضمين الرموز
                continue
            name = ggml_name(hf_name)
            data = tensor.squeeze().numpy().astype(np.float16)
            if name in ("encoder.conv1.bias", "encoder.conv2.bias"):
                data = data.reshape(data.shape[0], 1)
            n_dims = data.ndim
            ftype = 1
            if n_dims < 2 or name in F32_NAMES:
                data = data.astype(np.float32)
                ftype = 0
            encoded = name.encode("utf-8")
            fout.write(struct.pack("iii", n_dims, len(encoded), ftype))
            for i in range(n_dims):
                fout.write(struct.pack("i", data.shape[n_dims - 1 - i]))
            fout.write(encoded)
            data.tofile(fout)

    print(f"تم: {out} ({out.stat().st_size / 1e6:.1f} م.ب)")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)
    torch.set_grad_enabled(False)
    convert(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
