# Use Node 16 LTS (compatible with updated packages)
FROM node:16-bullseye

SHELL ["/bin/bash", "-c"]

# Install build dependencies
RUN apt-get update \
    && apt-get install -y python3 build-essential libcap2-bin\
    && apt-get -y autoclean

# Install global tools
RUN npm install -g pm2@5

RUN groupadd -r trinket && \
    useradd -r -g trinket -m -c "trinket user" trinket

RUN mkdir -p /usr/local/node/trinket && chown trinket:trinket /usr/local/node/trinket

# Allow the non-root trinket user to bind to privileged ports such as 443
RUN setcap 'cap_net_bind_service=+ep' "$(readlink -f "$(which node)")"

USER trinket

COPY --chown=trinket:trinket . /usr/local/node/trinket

WORKDIR /usr/local/node/trinket

# Download frontend components from GitHub release
RUN curl -L --silent -o ./public-components.tgz \
    https://github.com/trinketapp/trinket-oss/releases/download/v1.1.0/public-components.tgz \
    && tar xzf public-components.tgz \
    && rm public-components.tgz

# Build CSS elements to ensure correct rendering on modern browsers 
RUN npm install --legacy-peer-deps \
 && npm run build:css

# Adjust pathing to account for build inconsistencies when launching new trinkets
RUN sed -i "s|trinketConfig.getUrl('/library/trinkets/create?lang=' + lang)|'/library/trinkets/create?lang=' + lang|g" public/partials/directives/trinket.js


ARG COMMIT_ID
ARG NODE_ENV
ENV NODE_ENV=$NODE_ENV

EXPOSE 3000 443

CMD ["pm2-docker", "start", "app.js"]
