# Use Node 22 LTS on Debian Bookworm
FROM node:22-bookworm

SHELL ["/bin/bash", "-c"]

ENV NO_UPDATE_NOTIFIER=true

# Install build dependencies
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 build-essential libcap2-bin \
    && rm -rf /var/lib/apt/lists/*


# Install global tools
RUN npm install -g pm2@5 --no-audit --no-fund

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
    https://github.com/marc-hundley-oasisuk-org/trinket-oss/releases/download/public-components-baseline/public-components.tgz \
    && tar --warning=no-unknown-keyword -xzf public-components.tgz \
    && rm public-components.tgz


# Build CSS elements to ensure correct rendering on modern browsers 
RUN npm install --legacy-peer-deps --no-audit --no-fund \
 && npm run build:css

# Adjust pathing to account for build inconsistencies when launching new trinkets
RUN sed -i "s|trinketConfig.getUrl('/library/trinkets/create?lang=' + lang)|'/library/trinkets/create?lang=' + lang|g" public/partials/directives/trinket.js


ARG COMMIT_ID
ARG NODE_ENV
ENV NODE_ENV=$NODE_ENV

EXPOSE 3000 443

CMD ["pm2-docker", "start", "app.js"]
