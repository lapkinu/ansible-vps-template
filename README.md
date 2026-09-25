ansible-playbook playbooks/bootstrap.yml --ask-vault-pass
ansible-playbook playbooks/server.yml --syntax-check
ansible-playbook playbooks/server.yml --ask-vault-pass

sudo docker run -d --name test-nginx -p 8080:80 nginx
curl http://localhost:8080
curl http://192.168.56.10:8080

ansible-vault view inventory/production/group_vars/all/vault.yml
ansible-vault edit inventory/production/group_vars/all/vault.yml
