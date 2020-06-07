FROM alpine:3.10
#RUN apk update && apk add smokeping lighttpd curl bc perl-cgi && rm -rf /var/cache/apk/*
RUN apk update && \
    apk add smokeping lighttpd perl-cgi make curl bc ttf-dejavu && \
    rm -rf /var/cache/apk/*

# Tiny mod
RUN sed -i 's/"^/"/g' /etc/lighttpd/mod_cgi.conf

# Create directory if not exist
RUN [ -d /usr/data ] || mkdir -p /usr/data && \
    [ -d /usr/cache/smokeping ] || mkdir -p /usr/cache/smokeping

RUN mkdir -p /var/www/smokeping/cgi-bin && \
    cp -r /usr/share/webapps/smokeping/* /var/www/smokeping/cgi-bin/ && \
    ln -s /usr/cache/smokeping /var/www/smokeping/cgi-bin/cache

# Set permission and owners
RUN chown -R lighttpd:lighttpd /usr/data /usr/cache /var/www/smokeping
RUN chmod -R +rwx /usr/data /usr/cache /var/www/smokeping

# Copy my smokeping and lighttpd configuration files
COPY ./config /etc/smokeping/config
COPY ./lighttpd.conf /etc/lighttpd/lighttpd.conf

# Entrypoint script
COPY ./init.sh /tmp
RUN chmod +x /tmp/init.sh

# Expose port to host
EXPOSE 80
CMD /tmp/init.sh