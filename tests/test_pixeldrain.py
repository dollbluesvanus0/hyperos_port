import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("pixeldrain", Path(__file__).parents[1] / "ci/pixeldrain.py")
pixeldrain = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pixeldrain)


class PixeldrainTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.rom = Path(self.temp.name) / "test.zip"
        self.rom.write_bytes(b"fixture ROM")
        self.info = {"id": "Ab1234xy", "name": self.rom.name, "size": self.rom.stat().st_size,
                     "hash_sha256": hashlib.sha256(self.rom.read_bytes()).hexdigest()}

    def test_id_only_upload_response(self):
        self.assertEqual(pixeldrain.file_id({"id": "Ab1234xy"}), "Ab1234xy")

    def test_verify_metadata_without_success(self):
        self.assertEqual(pixeldrain.verify(self.info, self.rom, "Ab1234xy"), "Ab1234xy")

    def test_verify_metadata_with_success(self):
        self.info["success"] = True
        self.assertEqual(pixeldrain.verify(self.info, self.rom, "Ab1234xy"), "Ab1234xy")

    def test_explicit_error_rejected_even_with_id(self):
        for success in (False, None, "true", 1):
            with self.subTest(success=success), self.assertRaises(ValueError):
                pixeldrain.file_id({"id": "Ab1234xy", "success": success})

    def test_invalid_id_rejected(self):
        for identifier in (None, 1234, "", "../file", "abc\n", "a?b"):
            with self.subTest(identifier=identifier), self.assertRaises(ValueError):
                pixeldrain.file_id({"id": identifier})

    def test_wrong_size_rejected(self):
        self.info["size"] += 1
        with self.assertRaises(ValueError):
            pixeldrain.verify(self.info, self.rom, "Ab1234xy")

    def test_wrong_hash_rejected(self):
        self.info["hash_sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            pixeldrain.verify(self.info, self.rom, "Ab1234xy")

    def test_wrong_id_rejected(self):
        with self.assertRaises(ValueError):
            pixeldrain.verify(self.info, self.rom, "Other123")

    def test_find_exact_previous_upload(self):
        self.assertEqual(pixeldrain.find_existing({"files": [self.info]}, self.rom), "Ab1234xy")

    def test_same_name_different_content_is_not_reused(self):
        self.info["hash_sha256"] = "0" * 64
        self.assertEqual(pixeldrain.find_existing({"files": [self.info]}, self.rom), "")

    def test_invalid_file_list_rejected(self):
        for value in ([], {"files": None}, {"success": False, "files": [self.info]}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                pixeldrain.find_existing(value, self.rom)


if __name__ == "__main__":
    unittest.main()
