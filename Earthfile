test:
    FROM earthly/dind:alpine
    COPY on-host.sh .
    WITH DOCKER --pull "kindest/node:v1.21.1"
        RUN ./on-host.sh
    END

