ansible-playbook -i inventory/production/hosts.yml playbooks/bootstrap.yml
ansible-playbook playbooks/server.yml
ansible-playbook playbooks/server.yml --syntax-check
ansible-playbook playbooks/server.yml --ask-vault-pass

sudo docker run -d --name test-nginx -p 8080:80 nginx
curl http://localhost:8080
curl http://192.168.56.10:8080
