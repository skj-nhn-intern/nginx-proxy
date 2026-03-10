import { createContext, useContext, useState, useEffect } from 'react';
import { apiEndpoints, apiRequest } from '../config/api';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isInvitedUser, setIsInvitedUser] = useState(false);

  useEffect(() => {
    // 저장된 토큰으로 사용자 정보 복원
    const restoreUser = async () => {
      const token = localStorage.getItem('access_token');
      const invitedMode = localStorage.getItem('invitedMode');
      
      // 토큰이 있으면 먼저 사용자 정보 복원 시도
      if (token) {
        try {
          const response = await fetch(apiEndpoints.me(), {
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${token}`,
            },
          });
          if (response.ok) {
            const userData = await response.json();
            setUser(userData);
            setIsInvitedUser(false);
            if (invitedMode === 'true') {
              localStorage.removeItem('invitedMode');
              localStorage.removeItem('invitedAlbumId');
            }
          } else if (response.status === 401) {
            // 토큰 만료/무효일 때만 로그아웃 처리 (연속 새로고침 시 429/5xx/네트워크 오류로 토큰 삭제 방지)
            localStorage.removeItem('access_token');
            if (invitedMode === 'true') {
              setIsInvitedUser(true);
            }
          }
          // 429, 503 등 기타 오류: 토큰은 유지하고 로딩만 해제 (다음 요청/새로고침에서 재시도)
        } catch (error) {
          // 네트워크 오류 등: 토큰 유지, 로그아웃하지 않음
          console.error('Failed to restore user:', error);
          if (invitedMode === 'true') {
            setIsInvitedUser(true);
          }
        }
      } else if (invitedMode === 'true') {
        setIsInvitedUser(true);
      }
      
      setIsLoading(false);
    };

    restoreUser();
  }, []);

  const register = async (name, email, password) => {
    const response = await fetch(apiEndpoints.register(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email,
        username: name,
        password,
      }),
    });

    if (!response.ok) {
      if (response.status === 429) {
        throw new Error('요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.');
      }
      const error = await response.json().catch(() => ({ detail: '회원가입에 실패했습니다.' }));
      throw new Error(error.detail || '회원가입에 실패했습니다.');
    }

    return await response.json();
  };

  const login = async (email, password) => {
    const response = await fetch(apiEndpoints.login(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email, password }),
    });

    if (!response.ok) {
      if (response.status === 429) {
        throw new Error('요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.');
      }
      const error = await response.json().catch(() => ({ detail: '로그인에 실패했습니다.' }));
      throw new Error(error.detail || '이메일 또는 비밀번호가 올바르지 않습니다.');
    }

    const tokenData = await response.json();
    localStorage.setItem('access_token', tokenData.access_token);
    
    // 사용자 정보 가져오기
    const userData = await apiRequest(apiEndpoints.me());
    setUser(userData);
    setIsInvitedUser(false);
    localStorage.removeItem('invitedMode');
    
    return userData;
  };

  const logout = () => {
    setUser(null);
    setIsInvitedUser(false);
    localStorage.removeItem('access_token');
    localStorage.removeItem('invitedMode');
  };

  const setInvitedMode = (albumId) => {
    setIsInvitedUser(true);
    setUser(null);
    localStorage.setItem('invitedMode', 'true');
    localStorage.setItem('invitedAlbumId', albumId);
    localStorage.removeItem('access_token');
  };

  const clearInvitedMode = () => {
    setIsInvitedUser(false);
    localStorage.removeItem('invitedMode');
    localStorage.removeItem('invitedAlbumId');
  };

  const isAuthenticated = !!user && !isInvitedUser;

  const value = {
    user,
    isLoading,
    isAuthenticated,
    isInvitedUser,
    register,
    login,
    logout,
    setInvitedMode,
    clearInvitedMode,
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
