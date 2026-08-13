package com.back.domain.post.post.repository

import com.back.domain.post.post.service.PostService
import com.back.domain.post.postUser.service.PostUserService
import com.back.standard.extensions.getOrThrow
import jakarta.persistence.EntityManager
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.data.domain.PageRequest
import org.springframework.test.context.ActiveProfiles
import org.springframework.transaction.annotation.Transactional

/**
 * 하이브리드 검색 — "이 근처에서, 이 뜻에 가까운 글".
 *
 * 벡터DB 따로, 검색엔진 따로, 지도DB 따로 두면 이런 조건을 한 번에 못 건다.
 * PostgreSQL 하나에 다 있으니 WHERE 절에서 그냥 AND 로 묶으면 된다.
 */
@ActiveProfiles("test")
@SpringBootTest
@Transactional
class PostHybridSearchTest {
    @Autowired
    private lateinit var postRepository: PostRepository

    @Autowired
    private lateinit var postService: PostService

    @Autowired
    private lateinit var postUserService: PostUserService

    @Autowired
    private lateinit var em: EntityManager

    @Test
    @DisplayName("하이브리드, 반경 안에 있으면서 뜻이 가까운 글만 나온다")
    fun t1() {
        val author = postUserService.findByUsername("user1").getOrThrow()

        // 강남역 근처 + 음식 이야기 (정답)
        val answer = postService.write(
            author, "역삼동 김치찜", "묵은지와 삼겹살을 푹 끓인 집", 127.0364, 37.5004
        )
        // 강남역 근처지만 뜻이 멂
        postService.write(author, "역삼동 세무서 가는 길", "등기와 세금 신고 절차", 127.0365, 37.5005)
        // 뜻은 가깝지만 멀리 있음 (부산)
        postService.write(author, "부산 돼지국밥", "돼지고기를 푹 끓인 국밥", 129.0756, 35.1796)
        em.flush()

        val page = postRepository.findQPagedHybrid(
            kw = "김치찌개 맛집",
            lng = 127.0276, lat = 37.4979, radiusM = 3000.0,
            pageable = PageRequest.of(0, 5)
        )

        assertThat(page.content.map { it.title })
            .`as`("반경 밖(부산)은 빠지고, 반경 안에서 뜻이 가까운 글이 1등이어야 한다")
            .startsWith("역삼동 김치찜")
        assertThat(page.content.map { it.title }).doesNotContain("부산 돼지국밥")
        assertThat(page.content.map { it.id }).contains(answer.id)
    }
}
