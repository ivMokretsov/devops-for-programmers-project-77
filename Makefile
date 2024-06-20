.PHONY: init apply configure get-iam-token

init:
	cd terraform && terraform init

apply:
	cd terraform && terraform apply

configure:
	cd ansible && ansible-playbook -i inventory.yml playbook.yml --vault-pass-file ../.vault_pass

get-iam-token:
	cd ansible && ansible-playbook -i localhost get_iam_token.yml --vault-pass-file ../.vault_pass
