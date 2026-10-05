#!/usr/bin/env python3
"""Validate Pixeldrain IDs and verify published files against the local ROM."""
import hashlib
import json
import re
import sys
from pathlib import Path


def object_response(value):
    if not isinstance(value, dict):
        raise ValueError("Pixeldrain returned a non-object JSON response.")
    # Some successful endpoints omit success. An explicit error is never accepted.
    if "success" in value and value["success"] is not True:
        raise ValueError("Pixeldrain reported an unsuccessful request.")
    return value


def file_id(value):
    value = object_response(value)
    identifier = value.get("id")
    if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", identifier):
        raise ValueError("Pixeldrain did not return a valid file ID.")
    return identifier


def local_info(rom):
    digest = hashlib.sha256()
    with rom.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return rom.stat().st_size, digest.hexdigest()


def verify(value, rom, identifier):
    if file_id(value) != identifier:
        raise ValueError("Pixeldrain returned metadata for a different file ID.")
    size, digest = local_info(rom)
    if type(value.get("size")) is not int or value["size"] != size:
        raise ValueError("Pixeldrain file size does not match the local ROM.")
    if value.get("hash_sha256") != digest:
        raise ValueError("Pixeldrain SHA256 does not match the local ROM.")
    return identifier


def find_existing(value, rom):
    value = object_response(value)
    files = value.get("files")
    if not isinstance(files, list):
        raise ValueError("Pixeldrain did not return a file list.")
    size, digest = local_info(rom)
    for entry in files:
        if (isinstance(entry, dict) and entry.get("name") == rom.name
                and type(entry.get("size")) is int and entry["size"] == size
                and entry.get("hash_sha256") == digest):
            return file_id(entry)
    return ""


def main():
    try:
        command, response_path, *args = sys.argv[1:]
        value = json.loads(Path(response_path).read_text(encoding="utf-8"))
        if command == "id":
            print(file_id(value))
        elif command == "verify":
            print(verify(value, Path(args[0]), args[1]))
        elif command == "find":
            print(find_existing(value, Path(args[0])))
        else:
            raise ValueError("Unknown Pixeldrain validation command.")
    except (ValueError, OSError, IndexError) as error:
        sys.exit(str(error))


if __name__ == "__main__":
    main()
