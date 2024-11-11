# Use a lightweight base image
FROM alpine:latest

# Set the working directory
WORKDIR /app

# Install necessary packages
RUN apk add --no-cache bash curl dos2unix

# Copy the entire current directory into the container at /app
COPY . .

# Convert shell scripts & .env to Unix format
RUN dos2unix bin/*.sh
# RUN dos2unix bin/*.sh config.env

# Make the shell scripts executable
RUN chmod +x bin/*.sh

# The entry point for the application
CMD ["bash", "bin/check.sh"]