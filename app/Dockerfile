# Use the official .NET Core SDK image as the base image
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

# Set the working directory inside the container
WORKDIR /app

# Copy the project files to the container
COPY . .

# Restore the dependencies
RUN dotnet restore

# Build the project
RUN dotnet build --configuration Release --no-restore

# Publish the project
RUN dotnet publish --configuration Release --no-build --output /app/publish

# Use the official .NET Core runtime image as the base image
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime

# Set the working directory inside the container
WORKDIR /app

# Copy the published output from the build stage to the runtime stage
COPY --from=build /app/publish .

# Expose the port that the application listens on
EXPOSE 8080

# Set the entry point for the container
ENTRYPOINT ["dotnet", "RelayTest.dll"]
