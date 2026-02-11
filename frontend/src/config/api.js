/**
 * API Configuration
 *
 * 백엔드 API Base URL을 환경 변수 또는 기본값으로 관리합니다.
 * 프록시(/api)가 아니라 별도 도메인(https://api.example.com)으로 둘 수도 있습니다.
 *
 * 우선순위:
 * 1. VITE_API_BASE_URL (빌드 시)
 * 2. window.APP_CONFIG.apiBaseUrl (런타임)
 * 3. 개발 시 기본값: http://localhost:8000
 * 4. 프로덕션 기본값: /api (프록시 사용 시)
 *
 * URL 분리 배포 시: 빌드 시 또는 런타임에 전체 URL 설정
 * - 빌드 시: VITE_API_BASE_URL=https://api.example.com
 * - 런타임: index.html에 window.APP_CONFIG={apiBaseUrl:'https://api.example.com'};
 */

// Vite 환경 변수에서 API URL 가져오기
const getApiBaseUrl = () => {
  // 1. Vite 환경 변수 확인 (빌드 시 설정)
  if (import.meta.env.VITE_API_BASE_URL) {
    return import.meta.env.VITE_API_BASE_URL;
  }

  // 2. 런타임 설정 확인 (window.APP_CONFIG)
  if (typeof window !== 'undefined' && window.APP_CONFIG?.apiBaseUrl) {
    return window.APP_CONFIG.apiBaseUrl;
  }

  // 3. 개발 환경 기본값
  if (import.meta.env.DEV) {
    return 'http://localhost:8000';
  }

  // 4. 프로덕션 기본값 (프록시 사용 시 /api, URL 분리 시 빌드/런타임에서 설정)
  return '/api';
};

export const API_BASE_URL = getApiBaseUrl();

/**
 * 이미지 URL 반환. 상대 경로(백엔드 프록시)면 API_BASE_URL을 붙임.
 * @param {string} url - API에서 받은 photo.url (절대 URL 또는 /photos/.../image?t=...)
 */
export function getImageUrl(url) {
  if (!url) return '';
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return `${API_BASE_URL}${url}`;
}

/**
 * API 엔드포인트 헬퍼 함수
 */
export const apiEndpoints = {
  // Auth
  register: () => `${API_BASE_URL}/auth/register`,
  login: () => `${API_BASE_URL}/auth/login`,
  me: () => `${API_BASE_URL}/auth/me`,
  
  // Albums
  albums: () => `${API_BASE_URL}/albums/`,
  album: (id) => `${API_BASE_URL}/albums/${id}`,
  albumShare: (id) => `${API_BASE_URL}/albums/${id}/share`,
  
  // Photos
  photos: () => `${API_BASE_URL}/photos/`,
  photo: (id) => `${API_BASE_URL}/photos/${id}`,
  photosPresignedUrl: () => `${API_BASE_URL}/photos/presigned-url`,
  photosConfirm: () => `${API_BASE_URL}/photos/confirm`,
  
  // Share
  share: (token) => `${API_BASE_URL}/share/${token}`,
};

/**
 * API 요청 헬퍼 함수
 */
export const apiRequest = async (url, options = {}) => {
  const token = localStorage.getItem('access_token');
  
  const headers = {
    'Content-Type': 'application/json',
    ...options.headers,
  };

  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const response = await fetch(url, {
    ...options,
    headers,
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({ detail: '요청 처리 중 오류가 발생했습니다.' }));
    // 내부 정보 노출 방지: 사용자 친화적인 메시지만 반환
    const userFriendlyMessage = error.detail || '요청 처리 중 오류가 발생했습니다.';
    throw new Error(userFriendlyMessage);
  }

  return response.json();
};

// 개발 환경에서 API URL 로그 출력
if (import.meta.env.DEV) {
  console.log('API Base URL:', API_BASE_URL);
}

