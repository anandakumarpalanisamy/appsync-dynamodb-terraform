provider "aws" {
  region = "eu-west-2"
}

terraform {
  backend "s3" {
    bucket = "appsync-ddb-terraformstate"
    key    = "state"
    region = "eu-west-2"
  }
}

data "aws_caller_identity" "current" {}

resource "aws_dynamodb_table" "notes-table" {
  name = "notes"

  billing_mode = "PAY_PER_REQUEST"

  hash_key = "NoteId"

  attribute {
    name = "NoteId"
    type = "S"
  }
}

data "aws_dynamodb_table" "notes-table" {
  name = "notes"

  depends_on = [aws_dynamodb_table.notes-table]
}

resource "aws_iam_role" "notes-appsync-api-role" {
  name = "notes-appsync-api-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "appsync.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "notes-appsync-api-role-policy" {
  name = "notes-appsync-api-role-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:CreateItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = "${data.aws_dynamodb_table.notes-table.arn}"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_appsync_graphql_api.notes-api.arn}"
      }
    ]
  })

  depends_on = [aws_appsync_graphql_api.notes-api]
}

resource "aws_iam_role_policy_attachment" "notes-appysync-api-role-policy-assignment" {
  policy_arn = aws_iam_policy.notes-appsync-api-role-policy.arn
  role       = aws_iam_role.notes-appsync-api-role.name
}

resource "aws_appsync_graphql_api" "notes-api" {
  authentication_type = "API_KEY"
  name                = "NotesAPI"

  xray_enabled = true

  schema = file("./graphql/schema.graphql")

  log_config {
    exclude_verbose_content  = false
    field_log_level          = "ALL"
    cloudwatch_logs_role_arn = aws_iam_role.notes-appsync-api-role.arn
  }
}

resource "aws_cloudwatch_log_group" "notes-appsync-api-cloudwatch-log-group" {
  name              = "/aws/appsync/apis/${aws_appsync_graphql_api.notes-api.id}"
  retention_in_days = 7
}

resource "aws_appsync_datasource" "notes-api-ddb-datasource" {
  api_id           = aws_appsync_graphql_api.notes-api.id
  name             = "NotesAPI_AppSync_DDB_DataSource"
  service_role_arn = aws_iam_role.notes-appsync-api-role.arn
  type             = "AMAZON_DYNAMODB"

  dynamodb_config {
    table_name = aws_dynamodb_table.notes-table.name
    region     = var.region
  }
}

resource "aws_appsync_resolver" "all-notes-query-resolver" {
  api_id      = aws_appsync_graphql_api.notes-api.id
  field       = "allNotes"
  type        = "Query"
  data_source = aws_appsync_datasource.notes-api-ddb-datasource.name

  request_template = file("./resolvers/allnotes.request.vtl")

  response_template = file("./resolvers/allnotes.response.vtl")

  depends_on = [aws_appsync_graphql_api.notes-api]
}

resource "aws_appsync_resolver" "get-note-query-resolver" {
  api_id      = aws_appsync_graphql_api.notes-api.id
  field       = "getNote"
  type        = "Query"
  data_source = aws_appsync_datasource.notes-api-ddb-datasource.name

  request_template = file("./resolvers/getnote.request.vtl")

  response_template = file("./resolvers/generic.response.vtl")

  depends_on = [aws_appsync_graphql_api.notes-api]
}

resource "aws_appsync_resolver" "save-note-mutation-resolver" {
  api_id      = aws_appsync_graphql_api.notes-api.id
  field       = "saveNote"
  type        = "Mutation"
  data_source = aws_appsync_datasource.notes-api-ddb-datasource.name

  request_template = file("./resolvers/savenote.request.vtl")

  response_template = file("./resolvers/generic.response.vtl")

  depends_on = [aws_appsync_graphql_api.notes-api]
}

resource "aws_appsync_resolver" "delete-note-mutation-resolver" {
  api_id      = aws_appsync_graphql_api.notes-api.id
  field       = "deleteNote"
  type        = "Mutation"
  data_source = aws_appsync_datasource.notes-api-ddb-datasource.name

  request_template = file("./resolvers/deletenote.request.vtl")

  response_template = file("./resolvers/generic.response.vtl")

  depends_on = [aws_appsync_graphql_api.notes-api]
}