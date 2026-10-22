locals {
  function_name      = "${var.name}-query"
  knowledge_base_id  = module.knowledge_base.knowledge_base_ids["docs"]
  knowledge_base_arn = module.knowledge_base.knowledge_base_arns["docs"]
  guardrail_arn = var.guardrail_id == null ? null : (
    "arn:${data.aws_partition.current.partition}:bedrock:${var.region}:${local.suffix}:guardrail/${var.guardrail_id}"
  )
}

data "archive_file" "query" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/build/query.zip"
}

# Created explicitly (instead of letting Lambda create it on first log
# line) so retention is set and `terraform destroy` removes it.
resource "aws_cloudwatch_log_group" "query" {
  #checkov:skip=CKV_AWS_158:Demo logs hold request metadata only (no question text, see handler.py); default service-owned encryption is enough. Add kms_key_id for real data.
  #checkov:skip=CKV_AWS_338:30-day retention is a deliberate cost choice for a demo; raise log_retention_days for audit requirements.
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.suffix]
    }
  }
}

resource "aws_iam_role" "query" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "query" {
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.query.arn}:*"]
  }

  statement {
    sid       = "XRayTracing"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"] # X-Ray has no resource-level permissions for these actions.
  }

  # RetrieveAndGenerate has no resource type in the IAM Service
  # Authorization Reference, so it can only be granted on "*". What it can
  # reach is still bounded by the two statements below: Retrieve on this
  # one Knowledge Base, InvokeModel on this one model.
  statement {
    sid       = "RetrieveAndGenerate"
    actions   = ["bedrock:RetrieveAndGenerate"]
    resources = ["*"]
  }

  statement {
    sid       = "RetrieveFromThisKnowledgeBase"
    actions   = ["bedrock:Retrieve"]
    resources = [local.knowledge_base_arn]
  }

  # Cross-region inference: InvokeModel is checked against the inference
  # profile AND against the foundation model in whichever region the
  # request is routed to. The foundation model grant only applies when
  # called through this profile.
  statement {
    sid       = "InvokeThroughInferenceProfile"
    actions   = ["bedrock:InvokeModel"]
    resources = [data.aws_bedrock_inference_profile.generation.inference_profile_arn]
  }

  statement {
    sid       = "InvokeUnderlyingModels"
    actions   = ["bedrock:InvokeModel"]
    resources = [for m in data.aws_bedrock_inference_profile.generation.models : m.model_arn]
    condition {
      test     = "StringEquals"
      variable = "bedrock:InferenceProfileArn"
      values   = [data.aws_bedrock_inference_profile.generation.inference_profile_arn]
    }
  }

  dynamic "statement" {
    for_each = local.guardrail_arn == null ? [] : [local.guardrail_arn]
    content {
      sid       = "ApplyGuardrail"
      actions   = ["bedrock:ApplyGuardrail"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "query" {
  name   = "${local.function_name}-policy"
  role   = aws_iam_role.query.id
  policy = data.aws_iam_policy_document.query.json
}

resource "aws_lambda_function" "query" {
  #checkov:skip=CKV_AWS_117:No VPC on purpose - the function only calls Bedrock's public endpoint; a VPC would add NAT Gateway or interface endpoint cost without isolating anything here.
  #checkov:skip=CKV_AWS_116:Invoked synchronously through the function URL; a DLQ only applies to asynchronous invocations.
  #checkov:skip=CKV_AWS_272:Code signing needs an AWS Signer profile; out of scope for a demo deployed from source.
  #checkov:skip=CKV_AWS_173:Environment variables hold only resource IDs (no secrets); they are encrypted at rest with the AWS-managed key.
  function_name = local.function_name
  description   = "Answers questions over the ${var.name} Knowledge Base (Bedrock RetrieveAndGenerate)"
  role          = aws_iam_role.query.arn

  runtime       = "python3.13"
  architectures = ["arm64"]
  handler       = "handler.lambda_handler"

  filename         = data.archive_file.query.output_path
  source_code_hash = data.archive_file.query.output_base64sha256

  memory_size = 256
  timeout     = 30

  # Caps concurrent executions, which bounds Bedrock spend if the URL is
  # called in a loop.
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.query.name
  }

  environment {
    variables = {
      KNOWLEDGE_BASE_ID  = local.knowledge_base_id
      MODEL_ARN          = data.aws_bedrock_inference_profile.generation.inference_profile_arn
      NUMBER_OF_RESULTS  = tostring(var.number_of_results)
      GUARDRAIL_ID       = coalesce(var.guardrail_id, "")
      GUARDRAIL_VERSION  = var.guardrail_version
      MAX_QUESTION_CHARS = "1000"
    }
  }

  depends_on = [aws_iam_role_policy.query]
}

# AWS_IAM: every request must be SigV4-signed by a principal that holds
# query_caller_policy_document (see outputs.tf). Never NONE for an endpoint
# that spends money per call.
resource "aws_lambda_function_url" "query" {
  function_name      = aws_lambda_function.query.function_name
  authorization_type = "AWS_IAM"
}

# Since October 2025, function URLs require both lambda:InvokeFunctionUrl
# and lambda:InvokeFunction. The conditions keep each grant to the function
# URL path only - this policy cannot be used for a direct Invoke API call.
data "aws_iam_policy_document" "query_caller" {
  statement {
    sid       = "InvokeRagQueryUrl"
    actions   = ["lambda:InvokeFunctionUrl"]
    resources = [aws_lambda_function.query.arn]
    condition {
      test     = "StringEquals"
      variable = "lambda:FunctionUrlAuthType"
      values   = ["AWS_IAM"]
    }
  }

  statement {
    sid       = "InvokeOnlyViaFunctionUrl"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.query.arn]
    condition {
      test     = "Bool"
      variable = "lambda:InvokedViaFunctionUrl"
      values   = ["true"]
    }
  }
}
