ansible-playbook -i inventory/production/hosts.yml playbooks/bootstrap.yml
ansible-playbook playbooks/server.yml
