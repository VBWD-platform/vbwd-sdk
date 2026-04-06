# Sprint 06: User Cabinet (Full Stack TDD)

**Priority:** MEDIUM
**Duration:** 2-3 days
**Focus:** User profile management, subscription view, invoice history, plan selection
**Prerequisite:** Sprint 09 (Frontend Restructure)

> **Core Requirements:** TDD-first, SOLID, Liskov, DI, Clean Code

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              USER CABINET                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────── FRONTEND ──────────────────────────┐  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────┐   │  │
│  │  │   Profile   │  │Subscription │  │  Invoices   │  │  Plans  │   │  │
│  │  │   Store     │  │   Store     │  │   Store     │  │  Store  │   │  │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └────┬────┘   │  │
│  │         └────────────────┴────────────────┴──────────────┘        │  │
│  │                                │                                   │  │
│  │                    ┌───────────▼───────────┐                      │  │
│  │                    │    API Client         │                      │  │
│  │                    │ (@vbwd/view-component)│                      │  │
│  │                    └───────────┬───────────┘                      │  │
│  └────────────────────────────────┼──────────────────────────────────┘  │
│                                   │                                      │
│  ┌────────────────────────────────┼─────────────────────────────────┐   │
│  │                        BACKEND (Flask)                            │   │
│  │                    ┌───────────▼───────────┐                      │   │
│  │                    │   Routes (Blueprint)  │                      │   │
│  │                    │  /api/v1/profile      │                      │   │
│  │                    │  /api/v1/subscription │                      │   │
│  │                    │  /api/v1/invoices     │                      │   │
│  │                    └───────────┬───────────┘                      │   │
│  │                                │                                   │   │
│  │  ┌─────────────┐  ┌───────────▼───────────┐  ┌─────────────┐     │   │
│  │  │   Profile   │  │   Subscription        │  │   Invoice   │     │   │
│  │  │   Service   │  │   Service             │  │   Service   │     │   │
│  │  └──────┬──────┘  └───────────┬───────────┘  └──────┬──────┘     │   │
│  │         └────────────────────┬┴─────────────────────┘            │   │
│  │                              │                                    │   │
│  │                    ┌─────────▼─────────┐                         │   │
│  │                    │    PostgreSQL     │                         │   │
│  │                    └───────────────────┘                         │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 6.1 Profile Management

### Problem
No user profile editing functionality.

### Requirements
- View profile information
- Edit name, email, avatar
- Change password
- Delete account option (GDPR compliance)

---

### 6.1.1 Backend TDD Tests

**File:** `vbwd-backend/tests/unit/services/test_profile_service.py`
```python
import pytest
from unittest.mock import Mock, MagicMock
from datetime import datetime
from uuid import uuid4

from src.services.profile_service import ProfileService, ProfileUpdateData, ProfileResult
from src.models.user import User


class TestProfileService:
    """TDD tests for ProfileService - write these FIRST."""

    @pytest.fixture
    def user_repo(self):
        return Mock()

    @pytest.fixture
    def auth_service(self):
        return Mock()

    @pytest.fixture
    def service(self, user_repo, auth_service):
        return ProfileService(user_repo, auth_service)

    @pytest.fixture
    def sample_user(self):
        user = Mock(spec=User)
        user.id = uuid4()
        user.email = "john@example.com"
        user.name = "John Doe"
        user.avatar_url = None
        user.password_hash = "hashed_password"
        user.created_at = datetime.utcnow()
        user.is_active = True
        return user

    # GET PROFILE TESTS
    def test_get_profile_returns_user_data(self, service, user_repo, sample_user):
        """Profile endpoint returns user data."""
        user_repo.get_by_id.return_value = sample_user

        result = service.get_profile(str(sample_user.id))

        assert result.success is True
        assert result.user == sample_user
        user_repo.get_by_id.assert_called_once_with(str(sample_user.id))

    def test_get_profile_returns_error_for_nonexistent_user(self, service, user_repo):
        """Profile returns error when user not found."""
        user_repo.get_by_id.return_value = None

        result = service.get_profile("nonexistent-id")

        assert result.success is False
        assert result.error == "User not found"

    # UPDATE PROFILE TESTS
    def test_update_profile_changes_name(self, service, user_repo, sample_user):
        """Name update persists to database."""
        user_repo.get_by_id.return_value = sample_user

        result = service.update_profile(
            str(sample_user.id),
            ProfileUpdateData(name="Jane Doe")
        )

        assert result.success is True
        assert sample_user.name == "Jane Doe"
        user_repo.update.assert_called_once_with(sample_user)

    def test_update_profile_changes_email(self, service, user_repo, sample_user):
        """Email update persists to database."""
        user_repo.get_by_id.return_value = sample_user
        user_repo.get_by_email.return_value = None  # No existing user with email

        result = service.update_profile(
            str(sample_user.id),
            ProfileUpdateData(email="jane@example.com")
        )

        assert result.success is True
        assert sample_user.email == "jane@example.com"

    def test_update_profile_rejects_duplicate_email(self, service, user_repo, sample_user):
        """Duplicate email is rejected."""
        existing_user = Mock(spec=User)
        existing_user.id = uuid4()
        user_repo.get_by_id.return_value = sample_user
        user_repo.get_by_email.return_value = existing_user

        result = service.update_profile(
            str(sample_user.id),
            ProfileUpdateData(email="existing@example.com")
        )

        assert result.success is False
        assert result.error == "Email already in use"

    def test_update_profile_validates_email_format(self, service, user_repo, sample_user):
        """Invalid email format is rejected."""
        user_repo.get_by_id.return_value = sample_user

        result = service.update_profile(
            str(sample_user.id),
            ProfileUpdateData(email="invalid-email")
        )

        assert result.success is False
        assert "email" in result.error.lower()

    # CHANGE PASSWORD TESTS
    def test_change_password_requires_current_password(self, service, user_repo, auth_service, sample_user):
        """Password change needs current password verification."""
        user_repo.get_by_id.return_value = sample_user
        auth_service.verify_password.return_value = False

        result = service.change_password(
            str(sample_user.id),
            current_password="wrong_password",
            new_password="new_password123"
        )

        assert result.success is False
        assert result.error == "Current password incorrect"

    def test_change_password_hashes_new_password(self, service, user_repo, auth_service, sample_user):
        """New password is properly hashed."""
        user_repo.get_by_id.return_value = sample_user
        auth_service.verify_password.return_value = True
        auth_service.hash_password.return_value = "new_hashed_password"

        result = service.change_password(
            str(sample_user.id),
            current_password="old_password",
            new_password="new_password123"
        )

        assert result.success is True
        assert sample_user.password_hash == "new_hashed_password"
        auth_service.hash_password.assert_called_once_with("new_password123")

    def test_change_password_validates_minimum_length(self, service, user_repo, sample_user):
        """New password must meet minimum length requirement."""
        user_repo.get_by_id.return_value = sample_user

        result = service.change_password(
            str(sample_user.id),
            current_password="old_password",
            new_password="short"
        )

        assert result.success is False
        assert "8 characters" in result.error

    # DELETE ACCOUNT TESTS
    def test_delete_account_anonymizes_data(self, service, user_repo, sample_user):
        """Account deletion anonymizes user data (GDPR compliance)."""
        user_repo.get_by_id.return_value = sample_user

        result = service.delete_account(str(sample_user.id))

        assert result.success is True
        assert sample_user.email.startswith("deleted_")
        assert sample_user.name == "Deleted User"
        assert sample_user.avatar_url is None
        assert sample_user.is_active is False
        assert sample_user.deleted_at is not None

    def test_delete_account_returns_error_for_nonexistent_user(self, service, user_repo):
        """Delete returns error when user not found."""
        user_repo.get_by_id.return_value = None

        result = service.delete_account("nonexistent-id")

        assert result.success is False
        assert result.error == "User not found"
```

---

### 6.1.2 Backend Implementation

**File:** `vbwd-backend/src/services/profile_service.py`
```python
import re
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

from src.models.user import User
from src.repositories.user_repository import UserRepository
from src.services.auth_service import AuthService


@dataclass
class ProfileUpdateData:
    """Data transfer object for profile updates."""
    name: Optional[str] = None
    email: Optional[str] = None
    avatar_url: Optional[str] = None


@dataclass
class ProfileResult:
    """Result object for profile operations."""
    success: bool
    user: Optional[User] = None
    error: Optional[str] = None


class ProfileService:
    """
    Service for user profile management.

    Follows SOLID principles:
    - Single Responsibility: Only handles profile operations
    - Dependency Inversion: Depends on abstractions (repositories, services)
    """

    EMAIL_REGEX = re.compile(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
    MIN_PASSWORD_LENGTH = 8

    def __init__(
        self,
        user_repository: UserRepository,
        auth_service: AuthService
    ):
        self._user_repo = user_repository
        self._auth_service = auth_service

    def get_profile(self, user_id: str) -> ProfileResult:
        """Get user profile by ID."""
        user = self._user_repo.get_by_id(user_id)
        if not user:
            return ProfileResult(success=False, error="User not found")
        return ProfileResult(success=True, user=user)

    def update_profile(self, user_id: str, data: ProfileUpdateData) -> ProfileResult:
        """Update user profile with validation."""
        user = self._user_repo.get_by_id(user_id)
        if not user:
            return ProfileResult(success=False, error="User not found")

        # Validate and update email
        if data.email and data.email != user.email:
            if not self._is_valid_email(data.email):
                return ProfileResult(success=False, error="Invalid email format")

            existing = self._user_repo.get_by_email(data.email)
            if existing and str(existing.id) != user_id:
                return ProfileResult(success=False, error="Email already in use")
            user.email = data.email

        # Update other fields
        if data.name is not None:
            user.name = data.name

        if data.avatar_url is not None:
            user.avatar_url = data.avatar_url

        self._user_repo.update(user)
        return ProfileResult(success=True, user=user)

    def change_password(
        self,
        user_id: str,
        current_password: str,
        new_password: str
    ) -> ProfileResult:
        """Change user password with validation."""
        user = self._user_repo.get_by_id(user_id)
        if not user:
            return ProfileResult(success=False, error="User not found")

        # Validate new password length
        if len(new_password) < self.MIN_PASSWORD_LENGTH:
            return ProfileResult(
                success=False,
                error=f"New password must be at least {self.MIN_PASSWORD_LENGTH} characters"
            )

        # Verify current password
        if not self._auth_service.verify_password(current_password, user.password_hash):
            return ProfileResult(success=False, error="Current password incorrect")

        # Hash and save new password
        user.password_hash = self._auth_service.hash_password(new_password)
        self._user_repo.update(user)
        return ProfileResult(success=True, user=user)

    def delete_account(self, user_id: str) -> ProfileResult:
        """
        Delete user account with GDPR-compliant anonymization.

        Instead of hard delete, we anonymize user data to:
        - Preserve referential integrity
        - Maintain audit trails
        - Comply with GDPR right to erasure
        """
        user = self._user_repo.get_by_id(user_id)
        if not user:
            return ProfileResult(success=False, error="User not found")

        # Anonymize user data
        user.email = f"deleted_{user_id}@deleted.local"
        user.name = "Deleted User"
        user.avatar_url = None
        user.deleted_at = datetime.utcnow()
        user.is_active = False

        self._user_repo.update(user)
        return ProfileResult(success=True)

    def _is_valid_email(self, email: str) -> bool:
        """Validate email format."""
        return bool(self.EMAIL_REGEX.match(email))
```

**File:** `vbwd-backend/src/routes/profile.py`
```python
from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity

from src.services.profile_service import ProfileService, ProfileUpdateData

profile_bp = Blueprint("profile", __name__)


@profile_bp.route("/", methods=["GET"])
@jwt_required()
def get_profile():
    """Get current user's profile."""
    user_id = get_jwt_identity()
    service: ProfileService = current_app.container.profile_service()
    result = service.get_profile(user_id)

    if result.success:
        return jsonify({
            "id": str(result.user.id),
            "name": result.user.name,
            "email": result.user.email,
            "avatar_url": result.user.avatar_url,
            "created_at": result.user.created_at.isoformat()
        })
    return jsonify({"error": result.error}), 404


@profile_bp.route("/", methods=["PUT"])
@jwt_required()
def update_profile():
    """Update current user's profile."""
    user_id = get_jwt_identity()
    data = request.get_json()

    service: ProfileService = current_app.container.profile_service()
    result = service.update_profile(user_id, ProfileUpdateData(
        name=data.get("name"),
        email=data.get("email"),
        avatar_url=data.get("avatar_url")
    ))

    if result.success:
        return jsonify({"message": "Profile updated"})
    return jsonify({"error": result.error}), 400


@profile_bp.route("/password", methods=["PUT"])
@jwt_required()
def change_password():
    """Change current user's password."""
    user_id = get_jwt_identity()
    data = request.get_json()

    service: ProfileService = current_app.container.profile_service()
    result = service.change_password(
        user_id,
        data.get("current_password", ""),
        data.get("new_password", "")
    )

    if result.success:
        return jsonify({"message": "Password changed"})
    return jsonify({"error": result.error}), 400


@profile_bp.route("/", methods=["DELETE"])
@jwt_required()
def delete_account():
    """Delete current user's account."""
    user_id = get_jwt_identity()
    service: ProfileService = current_app.container.profile_service()
    result = service.delete_account(user_id)

    if result.success:
        return jsonify({"message": "Account deleted"})
    return jsonify({"error": result.error}), 400
```

---

### 6.1.3 Frontend TDD Tests

**File:** `vbwd-frontend/user/vue/tests/unit/stores/profile.spec.ts`
```typescript
import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { setActivePinia, createPinia } from 'pinia';
import { useProfileStore } from '@/stores/profile';
import type { IApiClient } from '@vbwd/view-component';

const mockApi = {
  get: vi.fn(),
  put: vi.fn(),
  delete: vi.fn(),
} as unknown as IApiClient;

describe('ProfileStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.resetAllMocks();
  });

  describe('Initial State', () => {
    it('initializes with null profile', () => {
      const store = useProfileStore();
      expect(store.profile).toBeNull();
    });

    it('initializes with loading false', () => {
      const store = useProfileStore();
      expect(store.loading).toBe(false);
    });

    it('initializes with null error', () => {
      const store = useProfileStore();
      expect(store.error).toBeNull();
    });
  });

  describe('fetchProfile', () => {
    it('sets loading true while fetching', async () => {
      const store = useProfileStore();
      mockApi.get = vi.fn().mockImplementation(
        () => new Promise(resolve => setTimeout(() => resolve({ data: {} }), 100))
      );
      store.setApiClient(mockApi);

      const promise = store.fetchProfile();
      expect(store.loading).toBe(true);
      await promise;
    });

    it('stores profile data on success', async () => {
      const store = useProfileStore();
      const profileData = {
        id: 'user-123',
        name: 'John Doe',
        email: 'john@example.com',
        avatar_url: null,
        created_at: '2024-01-15T00:00:00Z'
      };
      mockApi.get = vi.fn().mockResolvedValue({ data: profileData });
      store.setApiClient(mockApi);

      await store.fetchProfile();

      expect(store.profile).toEqual(profileData);
      expect(store.loading).toBe(false);
      expect(store.error).toBeNull();
    });

    it('sets error on failure', async () => {
      const store = useProfileStore();
      mockApi.get = vi.fn().mockRejectedValue(new Error('Network error'));
      store.setApiClient(mockApi);

      await store.fetchProfile();

      expect(store.profile).toBeNull();
      expect(store.error).toBe('Network error');
    });

    it('calls correct API endpoint', async () => {
      const store = useProfileStore();
      mockApi.get = vi.fn().mockResolvedValue({ data: {} });
      store.setApiClient(mockApi);

      await store.fetchProfile();

      expect(mockApi.get).toHaveBeenCalledWith('/api/v1/profile');
    });
  });

  describe('updateProfile', () => {
    it('updates profile name', async () => {
      const store = useProfileStore();
      store.profile = { id: '1', name: 'John', email: 'john@example.com' };
      mockApi.put = vi.fn().mockResolvedValue({ data: { message: 'Updated' } });
      store.setApiClient(mockApi);

      const result = await store.updateProfile({ name: 'Jane' });

      expect(result.success).toBe(true);
      expect(store.profile?.name).toBe('Jane');
    });

    it('validates email format', async () => {
      const store = useProfileStore();
      store.profile = { id: '1', name: 'John', email: 'john@example.com' };
      store.setApiClient(mockApi);

      const result = await store.updateProfile({ email: 'invalid-email' });

      expect(result.success).toBe(false);
      expect(result.error).toContain('email');
    });
  });

  describe('changePassword', () => {
    it('requires current password', async () => {
      const store = useProfileStore();
      store.setApiClient(mockApi);

      const result = await store.changePassword('', 'newpass123');

      expect(result.success).toBe(false);
      expect(result.error).toContain('current password');
    });

    it('validates minimum password length', async () => {
      const store = useProfileStore();
      store.setApiClient(mockApi);

      const result = await store.changePassword('oldpass', 'short');

      expect(result.success).toBe(false);
      expect(result.error).toContain('8 characters');
    });

    it('calls correct API endpoint', async () => {
      const store = useProfileStore();
      mockApi.put = vi.fn().mockResolvedValue({ data: { message: 'Changed' } });
      store.setApiClient(mockApi);

      await store.changePassword('oldpass123', 'newpass456');

      expect(mockApi.put).toHaveBeenCalledWith('/api/v1/profile/password', {
        current_password: 'oldpass123',
        new_password: 'newpass456'
      });
    });
  });

  describe('deleteAccount', () => {
    it('calls delete endpoint', async () => {
      const store = useProfileStore();
      mockApi.delete = vi.fn().mockResolvedValue({ data: { message: 'Deleted' } });
      store.setApiClient(mockApi);

      const result = await store.deleteAccount();

      expect(result.success).toBe(true);
      expect(mockApi.delete).toHaveBeenCalledWith('/api/v1/profile');
    });

    it('clears profile after deletion', async () => {
      const store = useProfileStore();
      store.profile = { id: '1', name: 'John', email: 'john@example.com' };
      mockApi.delete = vi.fn().mockResolvedValue({ data: {} });
      store.setApiClient(mockApi);

      await store.deleteAccount();

      expect(store.profile).toBeNull();
    });
  });

  describe('Computed Properties', () => {
    it('returns true for isLoaded when profile exists', () => {
      const store = useProfileStore();
      store.profile = { id: '1', name: 'John', email: 'john@example.com' };

      expect(store.isLoaded).toBe(true);
    });

    it('returns display name or email fallback', () => {
      const store = useProfileStore();
      store.profile = { id: '1', name: '', email: 'john@example.com' };

      expect(store.displayName).toBe('john@example.com');

      store.profile.name = 'John Doe';
      expect(store.displayName).toBe('John Doe');
    });
  });
});
```

---

### 6.1.4 Frontend Implementation

**File:** `vbwd-frontend/user/vue/src/stores/profile.ts`
```typescript
import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import type { IApiClient } from '@vbwd/view-component';

export interface Profile {
  id: string;
  name: string;
  email: string;
  avatar_url?: string | null;
  created_at?: string;
}

export interface ProfileUpdateData {
  name?: string;
  email?: string;
  avatar_url?: string;
}

export interface ProfileResult {
  success: boolean;
  error?: string;
}

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MIN_PASSWORD_LENGTH = 8;

export const useProfileStore = defineStore('profile', () => {
  // State
  const profile = ref<Profile | null>(null);
  const loading = ref(false);
  const error = ref<string | null>(null);
  let apiClient: IApiClient | null = null;

  // Computed
  const isLoaded = computed(() => profile.value !== null);
  const displayName = computed(() => {
    if (!profile.value) return '';
    return profile.value.name || profile.value.email;
  });

  // Actions
  function setApiClient(client: IApiClient) {
    apiClient = client;
  }

  async function fetchProfile(): Promise<void> {
    if (!apiClient) throw new Error('API client not set');

    loading.value = true;
    error.value = null;

    try {
      const response = await apiClient.get<Profile>('/api/v1/profile');
      profile.value = response.data;
    } catch (err: any) {
      error.value = err.message || 'Failed to fetch profile';
      profile.value = null;
    } finally {
      loading.value = false;
    }
  }

  async function updateProfile(data: ProfileUpdateData): Promise<ProfileResult> {
    if (!apiClient) throw new Error('API client not set');

    // Client-side validation
    if (data.email && !EMAIL_REGEX.test(data.email)) {
      return { success: false, error: 'Invalid email format' };
    }

    loading.value = true;

    try {
      await apiClient.put('/api/v1/profile', data);

      // Update local state optimistically
      if (profile.value) {
        if (data.name !== undefined) profile.value.name = data.name;
        if (data.email !== undefined) profile.value.email = data.email;
        if (data.avatar_url !== undefined) profile.value.avatar_url = data.avatar_url;
      }

      return { success: true };
    } catch (err: any) {
      const errorMsg = err.response?.data?.error || err.message || 'Failed to update';
      return { success: false, error: errorMsg };
    } finally {
      loading.value = false;
    }
  }

  async function changePassword(currentPassword: string, newPassword: string): Promise<ProfileResult> {
    if (!apiClient) throw new Error('API client not set');

    // Validation
    if (!currentPassword) {
      return { success: false, error: 'Please enter your current password' };
    }

    if (newPassword.length < MIN_PASSWORD_LENGTH) {
      return { success: false, error: `New password must be at least ${MIN_PASSWORD_LENGTH} characters` };
    }

    loading.value = true;

    try {
      await apiClient.put('/api/v1/profile/password', {
        current_password: currentPassword,
        new_password: newPassword
      });
      return { success: true };
    } catch (err: any) {
      const errorMsg = err.response?.data?.error || err.message || 'Failed to change password';
      return { success: false, error: errorMsg };
    } finally {
      loading.value = false;
    }
  }

  async function deleteAccount(): Promise<ProfileResult> {
    if (!apiClient) throw new Error('API client not set');

    loading.value = true;

    try {
      await apiClient.delete('/api/v1/profile');
      profile.value = null;
      return { success: true };
    } catch (err: any) {
      const errorMsg = err.response?.data?.error || err.message || 'Failed to delete account';
      return { success: false, error: errorMsg };
    } finally {
      loading.value = false;
    }
  }

  function $reset() {
    profile.value = null;
    loading.value = false;
    error.value = null;
  }

  return {
    // State
    profile,
    loading,
    error,

    // Computed
    isLoaded,
    displayName,

    // Actions
    setApiClient,
    fetchProfile,
    updateProfile,
    changePassword,
    deleteAccount,
    $reset
  };
});
```

**File:** `vbwd-frontend/user/vue/src/views/Profile.vue`
```vue
<template>
  <div class="profile-page">
    <h1>Profile Settings</h1>

    <Spinner v-if="profileStore.loading && !profileStore.profile" />

    <template v-else-if="profileStore.profile">
      <!-- Personal Information -->
      <Card>
        <template #header>
          <h2>Personal Information</h2>
        </template>

        <form @submit.prevent="saveProfile" data-testid="profile-form">
          <FormField label="Name" :error="errors.name">
            <Input
              v-model="form.name"
              placeholder="Your name"
              data-testid="name-input"
            />
          </FormField>

          <FormField label="Email" :error="errors.email">
            <Input
              v-model="form.email"
              type="email"
              placeholder="Your email"
              data-testid="email-input"
            />
          </FormField>

          <FormField label="Avatar URL" :error="errors.avatar_url">
            <Input
              v-model="form.avatar_url"
              placeholder="https://..."
              data-testid="avatar-input"
            />
          </FormField>

          <div class="form-actions">
            <Button type="submit" :loading="saving" data-testid="save-profile">
              Save Changes
            </Button>
          </div>
        </form>
      </Card>

      <!-- Change Password -->
      <Card class="mt-4">
        <template #header>
          <h2>Change Password</h2>
        </template>

        <form @submit.prevent="handleChangePassword" data-testid="password-form">
          <FormField label="Current Password" :error="passwordErrors.current">
            <Input v-model="passwordForm.current" type="password" data-testid="current-password" />
          </FormField>

          <FormField label="New Password" :error="passwordErrors.new">
            <Input v-model="passwordForm.new" type="password" data-testid="new-password" />
          </FormField>

          <FormField label="Confirm Password" :error="passwordErrors.confirm">
            <Input v-model="passwordForm.confirm" type="password" data-testid="confirm-password" />
          </FormField>

          <div class="form-actions">
            <Button type="submit" :loading="changingPassword" data-testid="change-password">
              Change Password
            </Button>
          </div>
        </form>
      </Card>

      <!-- Danger Zone -->
      <Card class="mt-4 danger-zone">
        <template #header>
          <h2>Danger Zone</h2>
        </template>

        <p>Deleting your account is permanent and cannot be undone.</p>
        <Button variant="danger" @click="showDeleteModal = true" data-testid="delete-account-btn">
          Delete Account
        </Button>
      </Card>
    </template>

    <!-- Delete Confirmation Modal -->
    <Modal v-model="showDeleteModal" title="Delete Account">
      <p>Are you sure you want to delete your account? This action cannot be undone.</p>
      <template #footer>
        <Button variant="ghost" @click="showDeleteModal = false">Cancel</Button>
        <Button variant="danger" @click="handleDeleteAccount" :loading="deleting" data-testid="confirm-delete">
          Delete Account
        </Button>
      </template>
    </Modal>

    <!-- Success Toast -->
    <Alert v-if="successMessage" variant="success" class="toast" data-testid="success-toast">
      {{ successMessage }}
    </Alert>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useProfileStore } from '@/stores/profile';
import { Button, Input, Card, Modal, FormField, Spinner, Alert } from '@vbwd/view-component';

const router = useRouter();
const profileStore = useProfileStore();

// Form state
const form = reactive({ name: '', email: '', avatar_url: '' });
const errors = reactive<Record<string, string>>({});
const saving = ref(false);

// Password form
const passwordForm = reactive({ current: '', new: '', confirm: '' });
const passwordErrors = reactive<Record<string, string>>({});
const changingPassword = ref(false);

// Delete state
const showDeleteModal = ref(false);
const deleting = ref(false);

// Toast
const successMessage = ref('');

onMounted(async () => {
  await profileStore.fetchProfile();
  if (profileStore.profile) {
    form.name = profileStore.profile.name || '';
    form.email = profileStore.profile.email || '';
    form.avatar_url = profileStore.profile.avatar_url || '';
  }
});

watch(() => profileStore.profile, (profile) => {
  if (profile) {
    form.name = profile.name || '';
    form.email = profile.email || '';
    form.avatar_url = profile.avatar_url || '';
  }
});

async function saveProfile() {
  saving.value = true;
  Object.keys(errors).forEach(key => delete errors[key]);

  const result = await profileStore.updateProfile({
    name: form.name,
    email: form.email,
    avatar_url: form.avatar_url || undefined
  });

  if (result.success) {
    showSuccess('Profile updated successfully');
  } else {
    errors.general = result.error || 'Failed to update';
  }
  saving.value = false;
}

async function handleChangePassword() {
  Object.keys(passwordErrors).forEach(key => delete passwordErrors[key]);

  if (passwordForm.new !== passwordForm.confirm) {
    passwordErrors.confirm = 'Passwords do not match';
    return;
  }

  changingPassword.value = true;
  const result = await profileStore.changePassword(passwordForm.current, passwordForm.new);

  if (result.success) {
    passwordForm.current = '';
    passwordForm.new = '';
    passwordForm.confirm = '';
    showSuccess('Password changed successfully');
  } else {
    passwordErrors.current = result.error || 'Failed to change password';
  }
  changingPassword.value = false;
}

async function handleDeleteAccount() {
  deleting.value = true;
  const result = await profileStore.deleteAccount();

  if (result.success) {
    showDeleteModal.value = false;
    router.push('/login');
  }
  deleting.value = false;
}

function showSuccess(message: string) {
  successMessage.value = message;
  setTimeout(() => { successMessage.value = ''; }, 3000);
}
</script>

<style scoped>
.profile-page { max-width: 800px; margin: 0 auto; padding: var(--spacing-lg); }
.mt-4 { margin-top: var(--spacing-xl); }
.form-actions { margin-top: var(--spacing-lg); display: flex; justify-content: flex-end; }
.danger-zone { border-color: var(--color-danger); }
.danger-zone h2 { color: var(--color-danger); }
.toast { position: fixed; bottom: var(--spacing-lg); right: var(--spacing-lg); z-index: 1000; }
</style>
```

---

## 6.2-6.4 Subscription, Invoices, Plans

See sections 6.2, 6.3, 6.4 in the original `todo/06-user-cabinet.md` for backend routes and frontend components. The pattern is the same:

1. **Write backend tests first** (pytest)
2. **Implement backend service** (ProfileService pattern)
3. **Write frontend store tests** (vitest)
4. **Implement frontend store** (Pinia)
5. **Create Vue component** with data-testid attributes

---

## Playwright E2E Tests

**File:** `vbwd-frontend/user/vue/tests/e2e/profile.spec.ts`
```typescript
import { test, expect } from '@playwright/test';

test.describe('Profile Management', () => {
  test.beforeEach(async ({ page }) => {
    // Login first
    await page.goto('/login');
    await page.fill('[data-testid="email"]', 'user@example.com');
    await page.fill('[data-testid="password"]', 'password123');
    await page.click('[data-testid="login-button"]');
    await page.waitForURL('/dashboard');
  });

  test('displays profile information', async ({ page }) => {
    await page.goto('/profile');
    await expect(page.locator('[data-testid="name-input"]')).toBeVisible();
    await expect(page.locator('[data-testid="email-input"]')).toBeVisible();
  });

  test('can update profile name', async ({ page }) => {
    await page.goto('/profile');
    await page.fill('[data-testid="name-input"]', 'New Name');
    await page.click('[data-testid="save-profile"]');
    await expect(page.locator('[data-testid="success-toast"]')).toBeVisible();
  });

  test('can change password', async ({ page }) => {
    await page.goto('/profile');
    await page.fill('[data-testid="current-password"]', 'password123');
    await page.fill('[data-testid="new-password"]', 'newpassword456');
    await page.fill('[data-testid="confirm-password"]', 'newpassword456');
    await page.click('[data-testid="change-password"]');
    await expect(page.locator('[data-testid="success-toast"]')).toBeVisible();
  });

  test('shows error for mismatched passwords', async ({ page }) => {
    await page.goto('/profile');
    await page.fill('[data-testid="current-password"]', 'password123');
    await page.fill('[data-testid="new-password"]', 'newpassword456');
    await page.fill('[data-testid="confirm-password"]', 'different');
    await page.click('[data-testid="change-password"]');
    await expect(page.locator('text=do not match')).toBeVisible();
  });
});
```

---

## Checklist

### 6.1 Profile Management
- [ ] Backend tests written (pytest) - TDD
- [ ] ProfileService implemented
- [ ] Profile routes created
- [ ] Frontend store tests written (vitest) - TDD
- [ ] Profile store implemented
- [ ] Profile.vue component
- [ ] E2E tests (Playwright)
- [ ] All tests pass

### 6.2 Subscription View
- [ ] Backend tests written - TDD
- [ ] Subscription routes (current, usage)
- [ ] Frontend store tests - TDD
- [ ] Subscription store
- [ ] Subscription.vue component
- [ ] E2E tests

### 6.3 Invoice History
- [ ] Backend tests written - TDD
- [ ] Invoice routes (list, PDF download)
- [ ] Frontend store tests - TDD
- [ ] Invoices store
- [ ] Invoices.vue component
- [ ] E2E tests

### 6.4 Plan Change UI
- [ ] Plans.vue component
- [ ] Proration calculation
- [ ] Upgrade/downgrade flow
- [ ] E2E tests

---

## Verification Commands

```bash
# Backend tests
cd vbwd-backend
docker-compose --profile test run --rm test pytest tests/unit/services/test_profile_service.py -v

# Frontend unit tests
cd vbwd-frontend/user
npm run test

# E2E tests
npm run test:e2e

# All tests with coverage
npm run test:coverage
```
