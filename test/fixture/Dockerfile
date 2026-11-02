FROM busybox:1.37
ARG COMMIT_SHA
RUN echo "$COMMIT_SHA" > /commit
CMD ["cat", "/commit"]
