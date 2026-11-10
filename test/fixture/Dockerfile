# BASE_TAG has no default, so the build fails unless the action passes the
# build-args input.
ARG BASE_TAG
FROM busybox:${BASE_TAG}
ARG COMMIT_SHA
# Fails unless the action passes the secrets input.
RUN --mount=type=secret,id=E2E_SECRET test -s /run/secrets/E2E_SECRET
RUN echo "$COMMIT_SHA" > /commit
CMD ["cat", "/commit"]
