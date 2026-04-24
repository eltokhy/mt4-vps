FROM alpine:3.20
RUN apk add --no-cache curl jq tzdata bash
COPY fetch.sh /fetch.sh
RUN chmod +x /fetch.sh
CMD ["sh", "-c", "while true; do /fetch.sh; sleep 3600; done"]
