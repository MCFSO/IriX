"""NPU smoke test for Intel AI Boost (Meteor Lake) via OpenVINO 2026.x.

Builds a tiny MLP programmatically (no model files, no downloads),
compiles it for CPU / NPU / GPU and runs inference, comparing latency.
"""
import time
import numpy as np
import openvino as ov
from openvino import opset13 as ops

rng = np.random.default_rng(42)
core = ov.Core()

# ---- build a small MLP: 256 -> 128 (relu) -> 64 ----
inp = ops.parameter([1, 256], np.float32, name="input")
w1 = ops.constant(rng.standard_normal((256, 128), dtype=np.float32) * 0.05)
b1 = ops.constant(rng.standard_normal((128,), dtype=np.float32) * 0.05)
h1 = ops.relu(ops.add(ops.matmul(inp, w1, False, False), b1))
w2 = ops.constant(rng.standard_normal((128, 64), dtype=np.float32) * 0.05)
b2 = ops.constant(rng.standard_normal((64,), dtype=np.float32) * 0.05)
out = ops.add(ops.matmul(h1, w2, False, False), b2)
model = ov.Model([out], [inp], "npu_smoke")

x = rng.standard_normal((1, 256), dtype=np.float32)

for dev in ["CPU", "GPU", "NPU"]:
    try:
        t0 = time.perf_counter()
        compiled = core.compile_model(model, dev)
        t_compile = time.perf_counter() - t0
        # warmup
        compiled([x])
        n = 20
        t0 = time.perf_counter()
        for _ in range(n):
            compiled([x])
        t_infer = (time.perf_counter() - t0) / n * 1000.0
        res = compiled([x])[0]
        print(f"[{dev:4s}] compile={t_compile*1000:8.1f} ms  infer={t_infer:8.3f} ms  "
              f"out={res.shape} mean={res.mean():.4f}")
    except Exception as e:
        print(f"[{dev:4s}] FAILED: {type(e).__name__}: {e}")

print("devices:", core.available_devices)
