"""Unit tests for handler.py. No AWS credentials or boto3 needed:
the Bedrock client is replaced with a fake before each test.

Run from examples/rag-e2e/lambda:  python -m unittest discover -s tests
"""

import base64
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

os.environ.update({
    "KNOWLEDGE_BASE_ID": "KB12345678",
    "MODEL_ARN": "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.amazon.nova-lite-v1:0",
    "NUMBER_OF_RESULTS": "4",
    "MAX_QUESTION_CHARS": "50",
})

import handler  # noqa: E402


class FakeClientError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


class FakeBedrock:
    def __init__(self, result=None, error=None):
        self.result, self.error, self.calls = result, error, []

    def retrieve_and_generate(self, **kwargs):
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        return self.result


def event(body, method="POST", b64=False):
    raw = json.dumps(body) if not isinstance(body, str) else body
    if b64:
        raw = base64.b64encode(raw.encode()).decode()
    return {"requestContext": {"http": {"method": method}}, "body": raw, "isBase64Encoded": b64}


RESULT = {
    "output": {"text": "Production deploys are frozen on Fridays after 14:00 UTC."},
    "sessionId": "sess-1",
    "citations": [
        {"retrievedReferences": [
            {"content": {"text": "Deploy freeze: Fridays after 14:00 UTC."},
             "location": {"s3Location": {"uri": "s3://bucket/docs/deployment-policy.md"}}},
        ]},
        {"retrievedReferences": [  # same chunk cited twice -> reported once
            {"content": {"text": "Deploy freeze: Fridays after 14:00 UTC."},
             "location": {"s3Location": {"uri": "s3://bucket/docs/deployment-policy.md"}}},
        ]},
    ],
}


class HandlerTest(unittest.TestCase):
    def setUp(self):
        handler.GUARDRAIL_ID = ""
        self.fake = FakeBedrock(result=RESULT)
        handler._client = self.fake

    def call(self, ev):
        res = handler.lambda_handler(ev, None)
        return res["statusCode"], json.loads(res["body"])

    def test_answers_with_deduplicated_citations(self):
        status, body = self.call(event({"question": "When are deploys frozen?"}))
        self.assertEqual(status, 200)
        self.assertIn("Fridays", body["answer"])
        self.assertEqual(body["session_id"], "sess-1")
        self.assertEqual(body["citations"], [{
            "source": "s3://bucket/docs/deployment-policy.md",
            "excerpt": "Deploy freeze: Fridays after 14:00 UTC.",
        }])

    def test_builds_the_bedrock_request_from_environment(self):
        self.call(event({"question": "  When are deploys frozen?  "}))
        req = self.fake.calls[0]
        self.assertEqual(req["input"], {"text": "When are deploys frozen?"})
        kb = req["retrieveAndGenerateConfiguration"]["knowledgeBaseConfiguration"]
        self.assertEqual(kb["knowledgeBaseId"], "KB12345678")
        self.assertTrue(kb["modelArn"].endswith("inference-profile/us.amazon.nova-lite-v1:0"))
        self.assertEqual(kb["retrievalConfiguration"]["vectorSearchConfiguration"]["numberOfResults"], 4)
        self.assertNotIn("generationConfiguration", kb)
        self.assertNotIn("sessionId", req)

    def test_passes_session_id_for_follow_up_questions(self):
        self.call(event({"question": "And on holidays?", "session_id": "sess-1"}))
        self.assertEqual(self.fake.calls[0]["sessionId"], "sess-1")

    def test_adds_guardrail_when_configured(self):
        handler.GUARDRAIL_ID = "gr-123"
        self.call(event({"question": "hi"}))
        kb = self.fake.calls[0]["retrieveAndGenerateConfiguration"]["knowledgeBaseConfiguration"]
        self.assertEqual(kb["generationConfiguration"]["guardrailConfiguration"]["guardrailId"], "gr-123")

    def test_accepts_base64_body(self):
        status, _ = self.call(event({"question": "hi"}, b64=True))
        self.assertEqual(status, 200)

    def test_rejects_bad_input_without_calling_bedrock(self):
        cases = [
            event({"question": "hi"}, method="GET"),
            event("not json"),
            event(["a list"]),
            event({}),
            event({"question": "   "}),
            event({"question": "x" * 51}),
            event({"question": "hi", "session_id": 7}),
        ]
        for ev in cases:
            with self.subTest(body=ev["body"], method=ev["requestContext"]["http"]["method"]):
                status, body = self.call(ev)
                self.assertEqual(status, 400)
                self.assertIn("error", body)
        self.assertEqual(self.fake.calls, [])

    def test_maps_throttling_to_429(self):
        handler._client = FakeBedrock(error=FakeClientError("ThrottlingException"))
        status, _ = self.call(event({"question": "hi"}))
        self.assertEqual(status, 429)

    def test_maps_other_bedrock_errors_to_502_with_code(self):
        handler._client = FakeBedrock(error=FakeClientError("AccessDeniedException"))
        status, body = self.call(event({"question": "hi"}))
        self.assertEqual(status, 502)
        self.assertIn("AccessDeniedException", body["error"])

    def test_never_logs_the_question_text(self):
        with self.assertLogs(level="INFO") as logs:
            self.call(event({"question": "my secret question"}))
        self.assertFalse(any("my secret question" in line for line in logs.output))


if __name__ == "__main__":
    unittest.main()
