package com.back.global.jpa.config

import org.slf4j.LoggerFactory
import org.springframework.boot.ApplicationRunner
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.core.annotation.Order
import javax.sql.DataSource

/**
 * JPA 어노테이션으로는 표현할 수 없는 인덱스(GIST, PGroonga, HNSW 등)를 부팅 시 만든다.
 *
 * `@Table(indexes = ...)` 은 `USING gist` 같은 인덱스 방식을 지정할 수 없기 때문에,
 * Hibernate 가 테이블을 만든 뒤(ddl-auto) 여기서 DDL 을 따로 실행한다.
 * 전부 `IF NOT EXISTS` 라서 몇 번을 재시작해도 안전하다.
 */
@Configuration
class DbIndexConfig {

    private val log = LoggerFactory.getLogger(javaClass)

    @Bean
    @Order(0)
    fun dbIndexRunner(dataSource: DataSource) = ApplicationRunner {
        val ddls = listOf(
            // 주변 검색(ST_DWithin)이 타는 인덱스.
            // geography 컬럼은 GIST 로 잡아야 반경 조건에서 후보를 좁힐 수 있다
            "CREATE INDEX IF NOT EXISTS idx_post_location_gist ON post USING gist (location)",
        )

        dataSource.connection.use { conn ->
            conn.autoCommit = true
            for (ddl in ddls) {
                runCatching {
                    conn.createStatement().use { it.execute(ddl) }
                    log.info("인덱스 확인/생성: {}", ddl)
                }.onFailure { ex ->
                    log.warn("인덱스 생성 실패: {} (DDL: {})", ex.message, ddl)
                }
            }
        }
    }
}
