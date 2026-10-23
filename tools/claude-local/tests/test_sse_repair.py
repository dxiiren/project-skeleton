"""Unit tests for the SSE tool-input repair in shim.py. Run: python -m unittest discover -s tools/claude-local/tests"""
import json
import os
import sys
import tempfile
import unittest

os.environ.setdefault("LOGDIR", tempfile.mkdtemp())
os.environ.setdefault("UPSTREAM", "http://127.0.0.1:1")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import shim  # noqa: E402

FIX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")


def relay(data: bytes, chunk: int = 7):
    """Feed data in odd-sized chunks, as a socket would, and return (output bytes, repairs)."""
    repairs = []
    r = shim.SSERepair(lambda i, suf, n: repairs.append((i, suf, n)))
    out = b""
    for k in range(0, len(data), chunk):
        out += b"".join(r.feed(data[k:k + chunk]))
    out += b"".join(r.flush())
    return out, repairs


def tool_inputs(sse: bytes):
    acc, order = {}, []
    for line in sse.decode().splitlines():
        if line.startswith("data:"):
            d = json.loads(line[5:])
            if d["type"] == "content_block_start" and d["content_block"]["type"] == "tool_use":
                acc[d["index"]] = ""
                order.append(d["index"])
            elif d["type"] == "content_block_delta" and d["delta"]["type"] == "input_json_delta":
                acc[d["index"]] += d["delta"]["partial_json"]
    return [acc[i] for i in order]


class RepairSuffix(unittest.TestCase):
    def test_valid_untouched(self):
        for t in ('{"a": 1}', "{}", '{"a": "}"}', "[1, 2]"):
            self.assertIsNone(shim.repair_suffix(t))

    def test_missing_brace(self):
        self.assertEqual(shim.repair_suffix('{"file_path": "a.txt"'), "}")

    def test_missing_quote_and_brace(self):
        self.assertEqual(shim.repair_suffix('{"file_path": "a.tx'), '"}')

    def test_nested_balance(self):
        t = '{"a": {"b": [1, 2'
        suf = shim.repair_suffix(t)
        self.assertEqual(suf, "]}}")
        json.loads(t + suf)

    def test_braces_inside_strings_ignored(self):
        t = '{"a": "x{[", "b": {"c": 1'
        self.assertEqual(shim.repair_suffix(t), "}}")

    def test_unrepairable(self):
        self.assertIsNone(shim.repair_suffix('{"a": }'))


class Stream(unittest.TestCase):
    def read(self, name):
        with open(os.path.join(FIX, name), "rb") as f:
            return f.read()

    def test_valid_stream_byte_identical(self):
        data = self.read("sglang_parallel_valid.sse")
        for chunk in (1, 7, 4096, len(data)):
            out, repairs = relay(data, chunk)
            self.assertEqual(out, data)
            self.assertEqual(repairs, [])

    def test_broken_stream_repaired(self):
        data = self.read("sglang_parallel_broken.sse")
        self.assertEqual(tool_inputs(data)[0], '{"file_path": "a.txt"')
        out, repairs = relay(data)
        self.assertEqual(len(repairs), 1)
        self.assertEqual(repairs[0][0:2], (2, "}"))
        ins = tool_inputs(out)
        self.assertEqual([json.loads(x) for x in ins], [{"file_path": "a.txt"}, {"file_path": "b.txt"}])

    def test_repair_event_precedes_stop_and_rest_identical(self):
        data = self.read("sglang_parallel_broken.sse")
        out, _ = relay(data)
        evs_in, evs_out = data.split(b"\n\n"), out.split(b"\n\n")
        self.assertEqual(len(evs_out), len(evs_in) + 1)
        k = next(i for i, e in enumerate(evs_out) if b'"partial_json": "}"' in e and b'"index": 2' in e)
        self.assertTrue(evs_out[k].startswith(b"event: content_block_delta\ndata: "))
        self.assertIn(b'"content_block_stop","index":2', evs_out[k + 1])
        del evs_out[k]
        self.assertEqual(evs_out, evs_in)

    def test_text_blocks_never_touched(self):
        ev = (b'event: content_block_start\ndata: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n'
              b'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"{\\"a\\""}}\n\n'
              b'event: content_block_stop\ndata: {"type":"content_block_stop","index":0}\n\n')
        out, repairs = relay(ev)
        self.assertEqual(out, ev)
        self.assertEqual(repairs, [])

    def test_empty_tool_input_untouched(self):
        ev = (b'event: content_block_start\ndata: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"x","name":"Read","input":{}}}\n\n'
              b'event: content_block_stop\ndata: {"type":"content_block_stop","index":2}\n\n')
        out, repairs = relay(ev)
        self.assertEqual(out, ev)
        self.assertEqual(repairs, [])

    def test_crlf_framing(self):
        data = self.read("sglang_parallel_broken.sse").replace(b"\n", b"\r\n")
        out, repairs = relay(data)
        self.assertEqual(len(repairs), 1)
        self.assertIn(b"event: content_block_delta\r\ndata: ", out)


if __name__ == "__main__":
    unittest.main()
