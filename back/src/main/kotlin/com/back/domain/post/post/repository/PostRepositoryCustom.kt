package com.back.domain.post.post.repository

import com.back.domain.post.post.entity.Post
import com.back.standard.dto.PostSearchKeywordType1
import org.springframework.data.domain.Page
import org.springframework.data.domain.Pageable

interface PostRepositoryCustom {
    fun findQPagedByKw(kwType: PostSearchKeywordType1, kw: String, pageable: Pageable): Page<Post>

    /** 주어진 좌표에서 radiusM 미터 안에 있는 글을 가까운 순으로 */
    fun findQPagedNearby(lng: Double, lat: Double, radiusM: Double, pageable: Pageable): Page<Post>
}
