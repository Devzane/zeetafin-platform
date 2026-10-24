[webservers]
${project_name}-${environment} ansible_host=${public_ip}

[webservers:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/phase1-key
ansible_python_interpreter=/usr/bin/python3
