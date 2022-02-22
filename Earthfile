systemd:
    FROM kindest/node:v1.21.1
    RUN mv /usr/local/bin/entrypoint /usr/local/bin/entrypoint.bkup

    # interpreter line
    RUN head -n 1 /usr/local/bin/entrypoint.bkup > /usr/local/bin/entrypoint

    # initial debug command
    RUN echo 'echo "entry point got $@"' >> /usr/local/bin/entrypoint

    # everything but first and last lines
    RUN cat /usr/local/bin/entrypoint.bkup | tail -n +2 | head -n -1 >> /usr/local/bin/entrypoint

    #RUN echo 'ls -la $@' >> /usr/local/bin/entrypoint # should say /sbin/init -> /usr/bin/systemd

    # final debug command
    RUN echo 'ls -la /sbin/init' >> /usr/local/bin/entrypoint
    RUN echo 'echo "about to run $@"' >> /usr/local/bin/entrypoint
    RUN echo 'exec "$@"' >> /usr/local/bin/entrypoint

    RUN head -n 2 /usr/local/bin/entrypoint | grep "point got"
    RUN tail -n 2 /usr/local/bin/entrypoint | grep "about to run"

    RUN chmod +x /usr/local/bin/entrypoint

    # This shouldn't be needed, as it's defined in kindest/node
    #ENTRYPOINT [ "/usr/local/bin/entrypoint", "/sbin/init" ]

test:
    FROM earthly/dind:alpine
    COPY on-host.sh .
    WITH DOCKER --load sd:latest=+systemd
        RUN --no-cache KEEP=1 IMG=sd ./on-host.sh
    END
