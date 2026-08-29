# Contributing

Local development workflow for this module. No AWS credentials are required
for any of the steps below.

## Prerequisites

- Terraform >= 1.7.0 to run the native test suite (`terraform test` relies
  on `mock_provider`, introduced in Terraform 1.7.0). The module's own
  runtime requirement, declared in `versions.tf`, remains `>= 1.5.0` -
  consumers who never run these tests are not affected by this floor.
- [tflint](https://github.com/terraform-linters/tflint)
- [checkov](https://www.checkov.io/)
- [terraform-docs](https://terraform-docs.io/) (only needed if you change
  `variables.tf` or `outputs.tf` and want to regenerate the README's
  reference tables locally)

## Workflow

```bash
terraform fmt -check -recursive

terraform init -backend=false
terraform validate
terraform test

tflint --recursive

checkov -d . --framework terraform
```

Checkov's expected soft-fail policy (targeted IDs, not a blanket
soft-fail) is defined in `.github/workflows/terraform-ci.yml` - see that
file for the current list and the justification for each ID.

Validate the example as its own root, separately:

```bash
cd examples/basic
terraform init -backend=false
terraform validate
```

## Regenerating documentation

If you change `variables.tf` or `outputs.tf`, regenerate the README's
generated Requirements/Providers/Resources/Inputs/Outputs tables:

```bash
terraform-docs -c .terraform-docs.yml .
```

Run it twice and confirm the second run produces no diff before
committing. CI runs `terraform-docs --output-check` and fails if the
README is stale - it does not auto-commit changes for you.

## CI

All of the above run in `.github/workflows/terraform-ci.yml` on every pull
request: `fmt`, `validate` (module root + example), `test`, `tflint`,
`checkov`, and the documentation-drift check.
