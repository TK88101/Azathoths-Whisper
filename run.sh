#!/bin/bash
export PYTHONPATH=$(pwd)/.venv/lib/python3.14/site-packages/aeosa
./.venv/bin/python3 lyrics_fetcher.py
