# Cobaltstrike Apache Redirector Docker

## Purpose Statement
Bash script for walking you through the creation of redirector rules for cobalstrike profiles.
There is also a dockerfile that you can use to containerize an Apache redirector server.

## DISCLAIMER
Usage of this script and dockerfile for attacking targets without prior mutual consent is illegal. This is only for educational or testing purposes and can only be used where strict consent has been given. It's the end user's responsibility to obey all applicable local, state and federal laws. Developers assume no liability and are not responsible for any misuse or damage caused by this program. Only use for educational or testing purposes.

## Getting Started

### System Requirements

A properly setup docker environment.

### Installing for development

Download the files via git and modify away!


Run the create config script to create the apache virtual host configuration file

```
./create_config.sh
```

Build the docker image

```
docker image build --tag apache-redirect .
```

Run the container

```
docker container run -p ${redirector_port_number}:${redirector_port_number} --name=apache-redirect --mount type=bind,source="$(pwd)"/certs,target=/certs --mount type=bind,source="$(pwd)"/conf,target=/conf --restart unless-stopped apache-redirect"
```


### Installing for Production

This will vary based on your docker environment. You will run the apache config script, build the image, then deploy it as a container.

Run the create config script to create the apache virtual host configuration file

```
./create_config.sh
```

Build the docker image

```
docker image build --tag apache-redirect .
```

Run the container

-- without mounts --
```
docker container run -p ${redirector_port_number}:${redirector_port_number} --name=apache-redirect --restart unless-stopped apache-redirect"
```
-- with mounts for auto updating config and certs --

```
docker container run -p ${redirector_port_number}:${redirector_port_number} --name=apache-redirect --mount type=bind,source="$(pwd)"/certs,target=/certs --mount type=bind,source="$(pwd)"/conf,target=/conf --restart unless-stopped apache-redirect"
```

### Requirements

After you build it, you can use it! But you need to have some information:

1. Know the IP or Domain Name of your CS Team Server
2. Know the C2 profile you want to use
3. Know required URI/UserAgent/custom identifiers used by beacon
4. A can do attitide

You need to have the specified redirector port clear on the docker host, or you need to change that port.

### Running the Container

```
docker container run -p ${redirector_port_number}:${redirector_port_number} --name=apache-redirect --mount type=bind,source="$(pwd)"/certs,target=/certs --mount type=bind,source="$(pwd)"/conf,target=/conf --restart unless-stopped apache-redirect"
```

| Parameter | Function |
| :----: | --- |
| `-p ${redirector_port_number}` | The port the redirector will listen on |
| `--mount [..]` | Bind mount for local conf and cert folders |


## Authors

* **@ditmer**


## References

* Information about Apache's mod_rewrite: https://httpd.apache.org/docs/current/mod/mod_rewrite.html
* This work is based on this write-up: https://bluescreenofjeff.com/2016-06-28-cobalt-strike-http-c2-redirectors-with-apache-mod_rewrite/
* Want profiles? Check this out https://github.com/rsmudge/Malleable-C2-Profiles

