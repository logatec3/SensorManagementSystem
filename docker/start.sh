#!/bin/bash

if [ -z "$EMAIL" ]; then
    echo "Email missing!"
else
    sed -i s/example@gmail.com/"$EMAIL"/g /etc/munin/munin.conf
    sed -i s/example@gmail.com/"$EMAIL"/g /etc/msmtprc
fi

if [ -z "$PASSWORD" ]; then
    echo "Email password missing!"
else
    sed -i s/secret/"$PASSWORD"/g /etc/msmtprc
fi

if [ -z "$SSH_AUTH_SOCK" ]; then
    echo "Consider adding ssh key!"
else
    sed -i \
    's|^#!/bin/bash|#!/bin/bash\n\nexport SSH_AUTH_SOCK='"$SSH_AUTH_SOCK"'|g' \
    /root/videk-hosts/videk-ping.sh
fi

if [ -z "$DOMAIN" ]; then
    echo "Consider adding domain name, default: localhost!"
else
    if [ -z "$WS" ]; then
        sed -i s/'localhost:3000'/"$DOMAIN"/g public/js/carvic.js
    fi
    sed -i s/'server_name localhost'/'server_name '"$DOMAIN"/g \
    /etc/nginx/conf.d/default.conf
    sed -i s/'localhost:4440'/"$DOMAIN"/g /etc/rundeck/rundeck-config.properties
fi

if [ -z "$WS" ]; then
    echo "Consider adding ws address, default: same as domain name!"
else
    sed -i s/'localhost:3000'/"$WS"/g public/js/carvic.js
fi

if [ -z "$RUNDECKP" ]; then
    echo "Consider changing the default rundeck password!"
else
    PASS="$(/root/rundeck/rundeckpass admin $RUNDECKP)"
    MD5="$(echo "$PASS" | grep -o -m 1 "MD5:[0-9a-f]\{32\}")"
    sed -i s/'^admin:.*'/'admin: '"$MD5"',user,admin'/g \
    /etc/rundeck/realm.properties
fi

if [ -z "$ANSIBLE_USER" ]; then
    echo "Ansible user missing!"
else
    sed -i 's/.*remote_user.*/remote_user = '"$ANSIBLE_USER"'/' \
    /etc/ansible/ansible.cfg
fi

if [ -z "$GITHUB_HOOK" ]; then
    echo "Consider adding github webhook service!"
else
    if [ "$GITHUB_TOKEN" = "" ] || [ "$SECRET_TOKEN" = "" ]; then
        echo "Github and/or secret webhook token missing!"
    else
        NGINX_CONF="/etc/nginx/conf.d/default.conf"
        sed -i '$ s/.$//' "$NGINX_CONF"
        echo -e "\tlocation /pyload {" >> "$NGINX_CONF"
        echo -e "\t\tproxy_pass http://localhost:"$GITHUB_HOOK";" \
        >> "$NGINX_CONF"
        echo -e "\t}\n}" >> "$NGINX_CONF"
        SUPERVISORD="/etc/supervisor/conf.d/supervisord.conf"
        echo -e "\n[program:github-webhook]" >> "$SUPERVISORD"
        echo -e "directory=/root/videk-ci" >> "$SUPERVISORD"
        echo -e "command=/root/videk-ci/github-webhook" "$GITHUB_TOKEN" >> "$SUPERVISORD"
        echo -e "stdout_logfile = /root/videk-ci/webhook.log" >> "$SUPERVISORD"
        echo -e "autorestart=true" >> "$SUPERVISORD"
        sed -i s/'port=8000'/"port=$GITHUB_HOOK"/g /root/videk-ci/github-webhook
    fi
fi

if [ -z "$MQTTP" ]; then
    echo "Consider adding mosquitto mqtt broker!"
else
    NGINX_CONF="/etc/nginx/conf.d/default.conf"
    sed -i '$ s/.$//' "$NGINX_CONF"
    echo -e "\tlocation /mqtt {" >> "$NGINX_CONF"
    echo -e "\t\tproxy_pass http://localhost:1884;" \
    >> "$NGINX_CONF"
    echo -e "\t\tproxy_http_version 1.1;" >> "$NGINX_CONF"
    echo -e "\t\tproxy_set_header Upgrade \$http_upgrade;" >> "$NGINX_CONF"
    echo -e "\t\tproxy_set_header Connection \"upgrade\";" >> "$NGINX_CONF"
    echo -e "\t}\n}" >> "$NGINX_CONF"
    SUPERVISORD="/etc/supervisor/conf.d/supervisord.conf"
    echo -e "\n[program:mosquitto]" >> "$SUPERVISORD"
    echo -e "directory=/root/videk-ci" >> "$SUPERVISORD"
    echo -e "command=/usr/sbin/mosquitto -c /etc/mosquitto/mosquitto.conf" \
    >> "$SUPERVISORD"
    echo -e "autorestart=true" >> "$SUPERVISORD"
    echo -e "videk:$MQTTP" >> /etc/mosquitto/auth
    mosquitto_passwd -U /etc/mosquitto/auth
fi

if [ -z "$GRAFANA" ]; then
    echo "Consider adding grafana service!"
else
    NGINX_CONF="/etc/nginx/conf.d/default.conf"
    sed -i '$ s/.$//' "$NGINX_CONF"
    echo -e "\tlocation /grafana/ {" >> "$NGINX_CONF"
    echo -e "\t\tproxy_pass http://$GRAFANA/;" >> "$NGINX_CONF"
    echo -e "\t}\n}" >> "$NGINX_CONF"
fi

if [ -z "$SCHEDULER" ]; then
    echo "Consider adding resource scheduler!"
else
    NGINX_CONF="/etc/nginx/conf.d/default.conf"
    sed -i '$ s/.$//' "$NGINX_CONF"
    echo -e "\tlocation /scheduler/ {" >> "$NGINX_CONF"
    echo -e "\t\tproxy_pass http://localhost:"$SCHEDULER"/;" >> "$NGINX_CONF"
    echo -e "\t}\n}" >> "$NGINX_CONF"

    SUPERVISORD="/etc/supervisor/conf.d/supervisord.conf"
    echo -e "\n[program:resource-scheduler]" >> "$SUPERVISORD"
    echo -e "directory=/root/testbed-scheduler" >> "$SUPERVISORD"
    echo -e "stdout_logfile = /root/testbed-scheduler/scheduler.log" >> "$SUPERVISORD"
    echo -e "autorestart=true" >> "$SUPERVISORD"
    echo -e "command=gunicorn --bind localhost:"$SCHEDULER" --worker-class eventlet -w 1 server:app" >> "$SUPERVISORD"

    #sed -i s/'port=8002'/"port=$SCHEDULER"/g /root/testbed-scheduler/server.py
fi

if [ -z "$EXPERIMENT_CONTROLLER" ]; then
    echo "Consider adding experiment controller and monitoring system!"
else
    NGINX_CONF="/etc/nginx/conf.d/default.conf"
    sed -i '$ s/.$//' "$NGINX_CONF"
    echo -e "\tlocation /controller/ {" >> "$NGINX_CONF"
    echo -e "\t\tinclude proxy_params;" >> "$NGINX_CONF"
    echo -e "\t\tproxy_pass http://localhost:"$EXPERIMENT_CONTROLLER"/;" >> "$NGINX_CONF"
    echo -e "\t\tproxy_set_header Host \$host;" >> "$NGINX_CONF"
    echo -e "\t\tproxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$NGINX_CONF"
    echo -e "\t\tproxy_set_header X-Forwarded-Proto \$scheme;" >> "$NGINX_CONF"
    echo -e "\t\tproxy_set_header X-Real-IP \$remote_addr;" >> "$NGINX_CONF"
    echo -e "\t\tproxy_buffering off;" >> "$NGINX_CONF"
    echo -e "\t\tproxy_http_version 1.1;" >> "$NGINX_CONF"
    echo -e "\t\tproxy_set_header Upgrade \$http_upgrade;" >> "$NGINX_CONF"
    echo -e '\t\tproxy_set_header Connection "upgrade";' >> "$NGINX_CONF"    
    echo -e "\t}\n}" >> "$NGINX_CONF"

    SUPERVISORD="/etc/supervisor/conf.d/supervisord.conf"
    echo -e "\n[program:experiment-controller]" >> "$SUPERVISORD"
    echo -e "directory=/root/logatec-experiment/monitoring" >> "$SUPERVISORD"
    echo -e "autorestart=true" >> "$SUPERVISORD"
    echo -e "command=gunicorn --bind localhost:"$EXPERIMENT_CONTROLLER" --worker-class eventlet -w 1 ECMS_server:app" >> "$SUPERVISORD"

    sed -i 's/CONTROLLER_HOSTNAME =.*/CONTROLLER_HOSTNAME = "tcp:\/\/193.2.205.19:5563"/1' \
    /root/logatec-experiment/monitoring/ECMS_server.py
fi

if [ "$HTTPS" = "true" ]; then
    if [ "$EMAIL" = "" ] || [ "$DOMAIN" = "" ]; then
        echo "Email and/or domain missing!"
    else
        service nginx start
        certbot -n --agree-tos --email "$EMAIL" --domains "$DOMAIN" \
        --redirect --keep-until-expiring --nginx
        service nginx stop

        if ! grep -q 'https' /etc/rundeck/rundeck-config.properties; then
            sed -i s/'http'/'https'/g /etc/rundeck/rundeck-config.properties
        fi

    fi
else
    echo "Consider using HTTPS!"
fi

exec /usr/bin/supervisord
