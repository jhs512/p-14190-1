# 빌드 스테이지: jangka512/pgj 기반 (테스트용 PG 내장)
FROM jangka512/pgj:latest AS builder

# JDK 25(Temurin) + Redis 설치 (Gradle은 gradlew 사용)
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl redis-server \
 && curl -sL "https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jdk/hotspot/normal/eclipse" -o /tmp/jdk.tar.gz \
 && mkdir -p /opt/java \
 && tar xzf /tmp/jdk.tar.gz -C /opt/java --strip-components=1 \
 && rm /tmp/jdk.tar.gz \
 && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/opt/java
ENV PATH="${JAVA_HOME}/bin:${PATH}"

WORKDIR /app

# 의존성 캐시 레이어 (소스 변경 시에도 캐시 유지)
COPY gradlew .
COPY gradle gradle
COPY build.gradle.kts settings.gradle.kts .
RUN chmod +x gradlew && ./gradlew dependencies --no-daemon

COPY src src

# PG 초기화 → 시작 → 테스트 DB 생성 → Redis 시작 → 빌드(테스트 포함) → PG 종료
RUN set -e \
 && PGDATA=/var/lib/postgresql/data \
 && mkdir -p "$PGDATA" && chown postgres:postgres "$PGDATA" \
 && su postgres -c "initdb -D $PGDATA --auth=trust" \
 && su postgres -c "pg_ctl -D $PGDATA start -o '-c listen_addresses=localhost' -w" \
 && su postgres -c "psql -c \"ALTER USER postgres PASSWORD 'lldj123414';\"" \
 && su postgres -c "psql -c \"CREATE DATABASE p_14190_1_test;\"" \
 && redis-server --daemonize yes --requirepass lldj123414 \
 && ./gradlew build --no-daemon \
 && su postgres -c "pg_ctl -D $PGDATA stop -w"

# 실행 스테이지
FROM container-registry.oracle.com/graalvm/jdk:25

ENV LANG=ko_KR.UTF-8
ENV LC_ALL=ko_KR.UTF-8
ENV JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8"

WORKDIR /app

COPY --from=builder /app/build/libs/*.jar app.jar

ENTRYPOINT ["java", "-Dspring.profiles.active=prod", "-jar", "app.jar"]
