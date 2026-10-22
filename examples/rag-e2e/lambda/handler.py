"""RAG query endpoint: Lambda function URL -> Bedrock RetrieveAndGenerate.

Request (POST, JSON):  {"question": "...", "session_id": "optional"}
Response (JSON):       {"answer": "...", "citations": [...], "session_id": "..."}

The question text is never logged - only its length - so the logs stay free
of whatever users type into it.
"""

import base64
import json
import logging
import os
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)

KNOWLEDGE_BASE_ID = os.environ.get("KNOWLEDGE_BASE_ID", "")
MODEL_ARN = os.environ.get("MODEL_ARN", "")
NUMBER_OF_RESULTS = int(os.environ.get("NUMBER_OF_RESULTS", "5"))
GUARDRAIL_ID = os.environ.get("GUARDRAIL_ID", "")
GUARDRAIL_VERSION = os.environ.get("GUARDRAIL_VERSION", "DRAFT")
MAX_QUESTION_CHARS = int(os.environ.get("MAX_QUESTION_CHARS", "1000"))
MAX_EXCERPT_CHARS = 300

_client = None


def _bedrock():
    """Created once per execution environment and reused across invocations."""
    global _client
    if _client is None:
        import boto3
        from botocore.config import Config

        _client = boto3.client(
            "bedrock-agent-runtime",
            config=Config(
                retries={"max_attempts": 3, "mode": "adaptive"},
                connect_timeout=5,
                read_timeout=25,  # below the 30 s function timeout
            ),
        )
    return _client


class BadRequest(Exception):
    pass


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }


def _parse(event):
    method = event.get("requestContext", {}).get("http", {}).get("method", "POST")
    if method != "POST":
        raise BadRequest("Use POST with a JSON body.")

    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    try:
        payload = json.loads(raw)
    except ValueError:
        raise BadRequest("Body must be valid JSON.")
    if not isinstance(payload, dict):
        raise BadRequest("Body must be a JSON object.")

    question = payload.get("question")
    if not isinstance(question, str) or not question.strip():
        raise BadRequest('"question" is required and must be a non-empty string.')
    question = question.strip()
    if len(question) > MAX_QUESTION_CHARS:
        raise BadRequest(f'"question" must be at most {MAX_QUESTION_CHARS} characters.')

    session_id = payload.get("session_id")
    if session_id is not None and not isinstance(session_id, str):
        raise BadRequest('"session_id" must be a string.')
    return question, session_id


def _request(question, session_id):
    kb_config = {
        "knowledgeBaseId": KNOWLEDGE_BASE_ID,
        "modelArn": MODEL_ARN,
        "retrievalConfiguration": {
            "vectorSearchConfiguration": {"numberOfResults": NUMBER_OF_RESULTS}
        },
    }
    if GUARDRAIL_ID:
        kb_config["generationConfiguration"] = {
            "guardrailConfiguration": {
                "guardrailId": GUARDRAIL_ID,
                "guardrailVersion": GUARDRAIL_VERSION,
            }
        }

    request = {
        "input": {"text": question},
        "retrieveAndGenerateConfiguration": {
            "type": "KNOWLEDGE_BASE",
            "knowledgeBaseConfiguration": kb_config,
        },
    }
    if session_id:
        request["sessionId"] = session_id
    return request


def _citations(result):
    """Flattens Bedrock's citations into one entry per retrieved chunk."""
    seen, out = set(), []
    for citation in result.get("citations", []):
        for ref in citation.get("retrievedReferences", []):
            uri = ref.get("location", {}).get("s3Location", {}).get("uri", "")
            text = ref.get("content", {}).get("text", "")
            key = (uri, text)
            if key in seen:
                continue
            seen.add(key)
            excerpt = text if len(text) <= MAX_EXCERPT_CHARS else text[:MAX_EXCERPT_CHARS] + "..."
            out.append({"source": uri, "excerpt": excerpt})
    return out


def lambda_handler(event, context):
    request_id = getattr(context, "aws_request_id", "local")
    try:
        question, session_id = _parse(event)
    except BadRequest as err:
        logger.info(json.dumps({"event": "bad_request", "request_id": request_id, "reason": str(err)}))
        return _response(400, {"error": str(err)})

    started = time.monotonic()
    try:
        result = _bedrock().retrieve_and_generate(**_request(question, session_id))
    except Exception as err:  # botocore ClientError and transport errors
        code = getattr(err, "response", {}).get("Error", {}).get("Code", type(err).__name__)
        logger.error(json.dumps({"event": "bedrock_error", "request_id": request_id, "error_code": code}))
        if code == "ThrottlingException":
            return _response(429, {"error": "Too many requests, retry shortly."})
        if code in ("ValidationException", "ResourceNotFoundException", "AccessDeniedException"):
            return _response(502, {"error": f"Knowledge Base query failed ({code})."})
        return _response(502, {"error": "Knowledge Base query failed."})

    citations = _citations(result)
    guardrail_action = result.get("guardrailAction")
    logger.info(json.dumps({
        "event": "answered",
        "request_id": request_id,
        "question_chars": len(question),
        "citations": len(citations),
        "guardrail_action": guardrail_action,
        "latency_ms": int((time.monotonic() - started) * 1000),
    }))
    return _response(200, {
        "answer": result.get("output", {}).get("text", ""),
        "citations": citations,
        "session_id": result.get("sessionId"),
        "guardrail_action": guardrail_action,
    })
