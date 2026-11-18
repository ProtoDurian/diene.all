# docker

durian.cloud > engineering > standards > docker

How Dockerfiles are built and published, one task set and one caller job per image

| Word | Means | Also called | See |
|---|---|---|---|
| Dockerfile key | The Dockerfile's own name; main for infra/Dockerfile and name for infra/name.Dockerfile. It keys the build, run and clean tasks. |  | [tag suffix](#tag-suffix) |
| tag suffix | The optional text passed after -- to a Docker task; it is appended to the local tag, such as local-1. |  | [Dockerfile key](#dockerfile-key) |

## Dockerfile key

## tag suffix
