#!/usr/bin/env python3
"""Asks the RAG endpoint a question with a SigV4-signed request.

Usage (from examples/rag-e2e, after apply + scripts/ingest.sh):
    python3 scripts/ask.py "When are production deploys frozen?"
    python3 scripts/ask.py --session <id> "And during the holidays?"

Needs boto3 and credentials for a principal that holds the
`query_caller_policy_document` output.
"""

import argparse
import json
import subprocess
import sys
import urllib.error
import urllib.request

import boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest


def terraform_output(name):
    return subprocess.run(
        ["terraform", "output", "-raw", name], check=True, capture_output=True, text=True
    ).stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("question")
    parser.add_argument("--session", help="session_id from a previous answer, for follow-up questions")
    parser.add_argument("--url", help="function URL (default: terraform output query_url)")
    args = parser.parse_args()

    url = args.url or terraform_output("query_url")
    region = url.split(".lambda-url.")[1].split(".")[0]
    body = {"question": args.question}
    if args.session:
        body["session_id"] = args.session
    data = json.dumps(body).encode()

    session = boto3.Session()
    request = AWSRequest(method="POST", url=url, data=data, headers={"Content-Type": "application/json"})
    SigV4Auth(session.get_credentials(), "lambda", region).add_auth(request)

    req = urllib.request.Request(url, data=data, headers=dict(request.headers), method="POST")
    try:
        with urllib.request.urlopen(req, timeout=35) as resp:
            result = json.load(resp)
    except urllib.error.HTTPError as err:
        print(f"HTTP {err.code}: {err.read().decode()}", file=sys.stderr)
        return 1

    print(result["answer"], "\n")
    for i, c in enumerate(result.get("citations", []), 1):
        print(f"[{i}] {c['source']}\n    {c['excerpt']}\n")
    print(f"session_id: {result.get('session_id')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
