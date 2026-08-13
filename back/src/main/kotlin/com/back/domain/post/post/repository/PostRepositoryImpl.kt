package com.back.domain.post.post.repository

import com.back.domain.post.post.entity.Post
import com.back.domain.post.post.entity.QPost
import com.back.global.jpa.config.SpatialFunctions
import com.back.global.jpa.config.VectorExpressions
import com.back.global.pGroonga.config.PGroongaExpressions
import org.springframework.ai.embedding.EmbeddingModel
import com.back.standard.dto.PostSearchKeywordType1
import com.back.standard.util.QueryDslUtil
import com.querydsl.jpa.impl.JPAQueryFactory
import org.springframework.data.domain.Page
import org.springframework.data.domain.Pageable
import org.springframework.data.support.PageableExecutionUtils

class PostRepositoryImpl(
    private val queryFactory: JPAQueryFactory,
    private val embeddingModel: EmbeddingModel,
) : PostRepositoryCustom {

    override fun findQPagedBySimilarity(kw: String, pageable: Pageable): Page<Post> {
        val post = QPost.post

        // 검색어도 글과 같은 방식으로 벡터로 만든다. 같은 공간에 놓여야 거리를 잴 수 있다
        val target = embeddingModel.embed(kw)
        val distance = VectorExpressions.cosineDistance(post.embedding, target)

        val results = queryFactory
            .selectFrom(post)
            .where(post.embedding.isNotNull)
            .orderBy(distance.asc())
            .offset(pageable.offset)
            .limit(pageable.pageSize.toLong())
            .fetch()

        val totalQuery = queryFactory
            .select(post.count())
            .from(post)
            .where(post.embedding.isNotNull)

        return PageableExecutionUtils.getPage(results, pageable) {
            totalQuery.fetchFirst() ?: 0L
        }
    }
    override fun findQPagedByKw(kwType: PostSearchKeywordType1, kw: String, pageable: Pageable): Page<Post> {
        val post = QPost.post

        val builder = com.querydsl.core.BooleanBuilder()

        if (kw.isNotBlank()) {
            when (kwType) {
                PostSearchKeywordType1.TITLE -> builder.and(post.title.containsIgnoreCase(kw))
                PostSearchKeywordType1.CONTENT -> builder.and(post.body.content.containsIgnoreCase(kw))
                PostSearchKeywordType1.AUTHOR_NAME -> builder.and(post.author.name.containsIgnoreCase(kw))
                PostSearchKeywordType1.ALL ->
                    builder.and(
                        post.title.containsIgnoreCase(kw)
                            .or(post.body.content.containsIgnoreCase(kw))
                            .or(post.author.name.containsIgnoreCase(kw))
                    )
            }
        }

        val query = queryFactory
            .selectFrom(post)
            .where(builder)

        QueryDslUtil.applySorting(query, pageable) { property ->
            when (property) {
                "id" -> post.id
                "authorName" -> post.author.name
                else -> null
            }
        }

        val results = query
            .offset(pageable.offset)
            .limit(pageable.pageSize.toLong())
            .fetch()

        val totalQuery = queryFactory
            .select(post.count())
            .from(post)
            .where(builder)

        return PageableExecutionUtils.getPage(results, pageable) {
            totalQuery.fetchFirst() ?: 0L
        }
    }

    override fun findQPagedHybrid(
        kw: String,
        lng: Double,
        lat: Double,
        radiusM: Double,
        pageable: Pageable
    ): Page<Post> {
        val post = QPost.post

        // 공간 인덱스로 후보를 좁히고(반경), 그 안에서 의미 거리로 줄 세운다.
        // 좁혀진 뒤에 벡터 거리를 재므로 전체를 훑지 않는다
        val within = SpatialFunctions.dWithin(post.location, lng, lat, radiusM)
        val distance = VectorExpressions.cosineDistance(post.embedding, embeddingModel.embed(kw))
        val where = post.location.isNotNull
            .and(post.embedding.isNotNull)
            .and(within)

        val results = queryFactory
            .selectFrom(post)
            .where(where)
            .orderBy(distance.asc())
            .offset(pageable.offset)
            .limit(pageable.pageSize.toLong())
            .fetch()

        val totalQuery = queryFactory
            .select(post.count())
            .from(post)
            .where(where)

        return PageableExecutionUtils.getPage(results, pageable) {
            totalQuery.fetchFirst() ?: 0L
        }
    }

    override fun findQPagedBySearchKw(kw: String, pageable: Pageable): Page<Post> {
        val post = QPost.post

        // ARRAY[title::text] &@~ '키워드' 로 렌더링된다 (CustomPostgreSQLDialect 에 등록한 함수)
        val match = PGroongaExpressions.match(kw, post.title)

        val results = queryFactory
            .selectFrom(post)
            .where(match)
            .orderBy(post.id.desc())
            .offset(pageable.offset)
            .limit(pageable.pageSize.toLong())
            .fetch()

        val totalQuery = queryFactory
            .select(post.count())
            .from(post)
            .where(match)

        return PageableExecutionUtils.getPage(results, pageable) {
            totalQuery.fetchFirst() ?: 0L
        }
    }

    override fun findQPagedNearby(lng: Double, lat: Double, radiusM: Double, pageable: Pageable): Page<Post> {
        val post = QPost.post

        // ST_DWithin 으로 후보를 좁히고(인덱스가 일하는 구간), 그 안에서만 정확한 거리로 정렬한다
        val within = SpatialFunctions.dWithin(post.location, lng, lat, radiusM)
        val distance = SpatialFunctions.distanceM(post.location, lng, lat)

        val results = queryFactory
            .selectFrom(post)
            .where(post.location.isNotNull.and(within))
            .orderBy(distance.asc())
            .offset(pageable.offset)
            .limit(pageable.pageSize.toLong())
            .fetch()

        val totalQuery = queryFactory
            .select(post.count())
            .from(post)
            .where(post.location.isNotNull.and(within))

        return PageableExecutionUtils.getPage(results, pageable) {
            totalQuery.fetchFirst() ?: 0L
        }
    }
}
