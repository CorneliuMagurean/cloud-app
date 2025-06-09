
FROM eclipse-temurin:17-jdk AS build
WORKDIR /app

COPY ./gradlew ./gradlew.bat ./settings.gradle.kts ./build.gradle.kts ./
COPY ./gradle ./gradle

COPY ./src ./src

RUN ./gradlew clean bootJar --no-daemon

FROM eclipse-temurin:17-jre-alpine AS runner
WORKDIR /app

COPY --from=build /app/build/libs/*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-XX:+UseG1GC", "-jar", "app.jar"]
