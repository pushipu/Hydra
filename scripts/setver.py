#!/usr/bin/env python3
"""Проставить "version" в manifest.json (единый источник — файл VERSION)."""
import json, sys
path, version = sys.argv[1], sys.argv[2]
data = json.load(open(path))
data["version"] = version
json.dump(data, open(path, "w"), indent=2, ensure_ascii=False)
