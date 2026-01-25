# cyberknight-council-template

## Building the Docker Image

The production build process (`server_build_script.sh`) requires a Docker image called `cyberknight-council-template-builder`. This image contains Ruby, Jekyll, and all necessary dependencies.

From within the project directory run the following to build it: `docker build -t cyberknight-council-template-builder .` 
