FROM debian:latest

ENV DEBIAN_FRONTEND noninteractive

# Install apache, PHP, and supplimentary programs. openssh-server, curl, and lynx-cur are for debugging the container.
RUN apt-get update && apt-get -y upgrade && apt-get -y install apache2

# Enable apache mods.
RUN a2enmod rewrite ssl proxy_html proxy proxy_http

# Manually set up the apache environment variables
ENV APACHE_RUN_USER www-data
ENV APACHE_RUN_GROUP www-data
ENV APACHE_LOG_DIR /var/log/apache2
ENV APACHE_LOCK_DIR /var/lock/apache2
ENV APACHE_PID_FILE /var/run/apache2.pid

# Update the default apache site with the config we created.
# ADD conf/apache-config.conf /etc/apache2/sites-enabled/000-default.conf

RUN mkdir /certs /conf
ADD certs /certs
ADD conf/apache_redirect.conf /conf/apache_redirect.conf
RUN ln -sf /conf/apache_redirect.conf /etc/apache2/sites-enabled/000-default.conf


# By default start up apache in the foreground, override with /bin/bash for interative.
CMD /usr/sbin/apache2ctl -D FOREGROUND
