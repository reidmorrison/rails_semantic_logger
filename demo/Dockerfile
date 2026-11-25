# The Rails Semantic Logger demo app, generated from this checkout by `rails new` with demo/template.rb.
# Build it from the repository root: docker compose -f demo/compose.yml up --build
FROM ruby:3.4-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev && \
    rm -rf /var/lib/apt/lists/*

RUN gem install rails --version "~> 8.1.0" --no-document

COPY . /rails_semantic_logger

RUN rails new /demo --skip-git --skip-docker --skip-kamal --skip-thruster --skip-ci --skip-test \
      --skip-system-test --skip-javascript --skip-asset-pipeline --skip-action-cable \
      --skip-active-storage --skip-action-mailbox --skip-action-text --skip-solid --skip-bootsnap \
      --skip-dev-gems --skip-brakeman --skip-rubocop --skip-bundler-audit \
      --template /rails_semantic_logger/demo/template.rb

WORKDIR /demo
ENV RAILS_ENV=development
EXPOSE 3000
CMD ["sh", "-c", "bin/rails db:prepare && exec bin/rails server --binding 0.0.0.0 --port 3000"]
