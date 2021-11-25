FROM ubuntu:focal

LABEL Maintainer="Grega Morano <grega.moranok@ijs.si>"
LABEL Description="This image is used to bootstrap Videk with all dependences"
LABEL Vendor="JSI"
LABEL Version="2.1"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Ljubljana

# Update packages and install some commons
RUN set -ex \
    && apt-get update --fix-missing \
    && apt-get upgrade -y \
    && apt-get install -y apt-utils \ 
                          supervisor \
                          rsync \
                          git \
                          wget \
                          cron \
                          curl \
                          zip \
                          make \
                          python-is-python2 \
                          software-properties-common \              
    && apt-get clean -y

# Install nodejs an npm
RUN set -ex \
    && apt-get install -y nodejs \
                          npm

# Install mongodb
RUN set -ex \ 
    && apt-get install -y mongodb
RUN mkdir -p /data/db

# Install nginx
RUN set -ex \
    && apt-get install -y nginx \
                          python3-certbot-nginx \
                          spawn-fcgi
RUN rm /etc/nginx/sites-enabled/default
COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf

# Install munin
RUN set -ex \ 
    && apt-get install -y munin
RUN sed -e '/background 1/ s/^#*/# /' -i /etc/munin/munin-node.conf \
    && sed -i 's/^\(setsid \).*/\10/' /etc/munin/munin-node.conf \
    && mkdir -p /var/run/munin \
    && chown munin /var/run/munin \
    && chmod 755 /var/run/munin \
    && mkdir -p /var/cache/munin/www \
    && chown munin /var/cache/munin/www \
    && chmod 755 /var/cache/munin/www \
    && mkdir -p /var/lib/munin \
    && chown munin /var/lib/munin \
    && chmod 755 /var/lib/munin
COPY docker/munin/munin.conf /etc/munin/munin.conf

# Install email support and setup munin alert
RUN set -ex \ 
    && apt-get install -y msmtp-mta \
                          mailutils
COPY docker/munin/msmtprc /etc/msmtprc

# Install ansible
RUN set -ex \ 
    && apt-get install -y ansible
COPY docker/ansible/hosts /etc/ansible/hosts

# Install rundeck
#RUN set -ex \
#    && wget -O /tmp/rundeck.deb https://dl.bintray.com/rundeck/rundeck-deb/rundeck_3.3.2.20200817-1_all.deb \
#    && dpkg -i /tmp/rundeck.deb
RUN set -ex \
    && curl -L https://packages.rundeck.com/pagerduty/rundeck/gpgkey | apt-key add - \
    && echo "deb https://packages.rundeck.com/pagerduty/rundeck/any/ any main" >> /etc/apt/sources.list.d/rundeck.list \
    && echo "deb-src https://packages.rundeck.com/pagerduty/rundeck/any/ any main" >> /etc/apt/sources.list.d/rundeck.list \
    && apt-get update \
    && apt-get install -y expect \
                          uuid-runtime \
                          openjdk-11-jre-headless \
                          rundeck
COPY docker/rundeck/rundeck-config.properties /etc/rundeck/rundeck-config.properties
COPY docker/rundeck/profile /etc/rundeck/profile
COPY docker/rundeck/rundeckd /root/rundeck/rundeckd
COPY docker/rundeck/rundeckpass /root/rundeck/rundeckpass

# Install Jenkins
RUN set -ex \
    && wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key | apt-key add - \
    && sh -c "echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list"
RUN set -ex \
    && apt-get update \
    && apt-get install -y jenkins
ENV JENKINS_HOME /var/lib/jenkins

# Install Videk cron to sync hosts
RUN cd /root \
    && git clone https://github.com/logatec3/videk-hosts.git \
    && touch /etc/cron.d/videk-hosts \
    && echo "*/5 * * * * root /usr/bin/python3 /root/videk-hosts/videk-hosts.py" >> /etc/cron.d/videk-hosts \
    && touch /etc/cron.d/videk-ping \
    && echo "*/10 * * * * root /root/videk-hosts/videk-ping.sh" >> /etc/cron.d/videk-ping

# Install Videk CI
RUN cd /root \
    && git clone https://github.com/logatec3/videk-ci.git

# Install ECMS tool
RUN set -ex \
    && apt-get install -y python3-pip \
    && pip3 install flask \
                    flask-socketio \
                    eventlet==0.30.2 \
                    pyzmq \
                    gunicorn
RUN cd /root \
    && git clone --single-branch --branch master https://github.com/logatec3/logatec-experiment.git

# Install Mosquitto mqtt broker
RUN set -ex \
    && apt-get install -y mosquitto \
                          mosquitto-clients 
COPY docker/mosquitto/videk.conf /etc/mosquitto/conf.d

# Install testbed resource scheduler
RUN set -ex \
    && pip3 install pymongo \
                    python-dateutil 
RUN cd /root \
    && git clone https://github.com/logatec3/testbed-scheduler.git

# Install Videk master from github
RUN cd /root \
    && git clone https://github.com/logatec3/SensorManagementSystem.git
WORKDIR /root/SensorManagementSystem
RUN npm install
RUN /usr/bin/mongod --fork --logpath /var/log/mongodb.log --dbpath /data/db \
    && nodejs app.js init -y \
    && /usr/bin/mongod --shutdown

# ssh setup
RUN mkdir -p /root/.ssh
RUN chmod 700 /root/.ssh \
    && touch /root/.ssh/config \
    && echo "Host *" >> /root/.ssh/config \
    && echo "    StrictHostKeyChecking no" >> /root/.ssh/config

# volumes
VOLUME ["/data/db", "/etc/munin", "/var/lib/munin", "/var/cache/munin/www", \
"/etc/ansible", "/etc/rundeck", "/var/rundeck", "/var/lib/rundeck", \
"/etc/letsencrypt", "/var/lib/jenkins"]

COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/start.sh /root/start.sh
RUN chmod 755 /root/start.sh

ENTRYPOINT ["/root/start.sh"]
