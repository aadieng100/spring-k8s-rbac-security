# ==========================================
# Stage 1: Build the application (Maven)
# ==========================================
FROM maven:3.9.6-eclipse-temurin-21-alpine AS builder
WORKDIR /app

# Copy only the pom.xml to cache Maven dependencies
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy sources and build the jar file (skipping tests for speed)
COPY src ./src
RUN mvn clean package -DskipTests

# ==========================================
# Stage 2: Runtime Environment (JRE)
# ==========================================
FROM eclipse-temurin:21-jre-alpine AS runner

# Create a dedicated non-root system group and user with explicit UID/GID 1000
# to align perfectly with the Kubernetes securityContext (runAsUser/runAsGroup)
RUN addgroup -g 1000 -S spring && adduser -u 1000 -S spring -G spring

WORKDIR /app

# Copy the compiled jar from the builder stage
# Change file ownership directly during copy to the non-root user
COPY --from=builder --chown=spring:spring /app/target/secure-api-1.0.0.jar app.jar

# Switch to the non-root execution user context
USER spring:spring

# Expose the default Spring Boot application port
EXPOSE 8080

# Optimize JVM settings for container environments:
# - UseContainerSupport: ensures JVM respects container memory and CPU limits
ENTRYPOINT ["java", "-XX:+UseContainerSupport", "-jar", "app.jar"]
