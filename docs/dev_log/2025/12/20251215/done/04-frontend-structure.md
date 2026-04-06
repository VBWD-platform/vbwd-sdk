# Task 04: Frontend Structure (Vue.js)

**Priority:** High
**Status:** Pending
**Estimated Effort:** Large

---

## Objective

Create the Vue.js application structures for both user and admin frontends.

---

## Tasks

### 4.1 Create frontend/user/vue/package.json

```json
{
  "name": "vbwd-user",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "test": "vitest",
    "lint": "eslint . --ext .vue,.js,.jsx,.cjs,.mjs --fix"
  },
  "dependencies": {
    "vue": "^3.4.0",
    "vue-router": "^4.2.5",
    "pinia": "^2.1.7",
    "socket.io-client": "^4.7.2",
    "axios": "^1.6.2"
  },
  "devDependencies": {
    "@vitejs/plugin-vue": "^4.5.2",
    "vite": "^5.0.8",
    "vitest": "^1.1.0",
    "eslint": "^8.56.0",
    "eslint-plugin-vue": "^9.19.2"
  }
}
```

### 4.2 Create frontend/user/vue/src/App.vue

```vue
<template>
  <div id="app">
    <router-view />
  </div>
</template>

<script setup>
// Main App component - minimal, routes handle views
</script>

<style>
#app {
  font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
  max-width: 800px;
  margin: 0 auto;
  padding: 20px;
}
</style>
```

### 4.3 Create frontend/user/vue/src/views/SubmissionWizard.vue

```vue
<template>
  <div class="wizard">
    <div class="steps">
      <span :class="{ active: step === 1, completed: step > 1 }">1. Upload</span>
      <span :class="{ active: step === 2, completed: step > 2 }">2. Contact</span>
      <span :class="{ active: step === 3 }">3. Confirm</span>
    </div>

    <!-- Step 1: Upload Images -->
    <div v-if="step === 1" class="step-content">
      <h2>Upload Your Images</h2>
      <input
        type="file"
        multiple
        accept="image/jpeg,image/png,image/webp"
        @change="handleFileUpload"
      />
      <div v-if="images.length" class="preview">
        <div v-for="(img, i) in images" :key="i" class="preview-item">
          <img :src="img.preview" alt="Preview" />
          <button @click="removeImage(i)">Remove</button>
        </div>
      </div>
      <textarea
        v-model="comments"
        placeholder="Add any comments about your images..."
      ></textarea>
      <button @click="nextStep" :disabled="!images.length">Next</button>
    </div>

    <!-- Step 2: Contact & Consent -->
    <div v-if="step === 2" class="step-content">
      <h2>Contact Information</h2>
      <input
        v-model="email"
        type="email"
        placeholder="Your email address"
      />
      <div class="consent">
        <h3>Data Processing Agreement</h3>
        <p>By submitting, you agree to our data processing terms...</p>
        <label>
          <input type="checkbox" v-model="consent" />
          I agree to the data processing terms
        </label>
      </div>
      <div class="buttons">
        <button @click="prevStep">Back</button>
        <button @click="submitData" :disabled="!canSubmit">Submit</button>
      </div>
    </div>

    <!-- Step 3: Confirmation -->
    <div v-if="step === 3" class="step-content">
      <h2>Submission Received</h2>
      <p>Your data has been submitted successfully.</p>
      <p>You will receive results via email at <strong>{{ email }}</strong></p>

      <div v-if="statusMessage" class="status-update">
        <p>Status: {{ statusMessage }}</p>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useSubmissionStore } from '@/stores/submission'
import { io } from 'socket.io-client'

const store = useSubmissionStore()

const step = ref(1)
const images = ref([])
const comments = ref('')
const email = ref('')
const consent = ref(false)
const statusMessage = ref('')
const socket = ref(null)

const canSubmit = computed(() => email.value && consent.value)

function handleFileUpload(event) {
  const files = Array.from(event.target.files)
  files.forEach(file => {
    const reader = new FileReader()
    reader.onload = (e) => {
      images.value.push({
        file,
        preview: e.target.result,
        type: file.type,
        size: file.size
      })
    }
    reader.readAsDataURL(file)
  })
}

function removeImage(index) {
  images.value.splice(index, 1)
}

function nextStep() {
  step.value++
}

function prevStep() {
  step.value--
}

async function submitData() {
  try {
    const result = await store.submit({
      images: images.value.map(img => ({
        data: img.preview,
        type: img.type,
        size: img.size
      })),
      comments: comments.value,
      email: email.value,
      consent: consent.value
    })

    step.value = 3

    // Connect WebSocket for live updates
    connectSocket()

  } catch (error) {
    alert('Submission failed: ' + error.message)
  }
}

function connectSocket() {
  socket.value = io()

  socket.value.emit('subscribe', { email: email.value })

  socket.value.on('status_update', (data) => {
    statusMessage.value = data.message
  })

  socket.value.on('result_ready', () => {
    statusMessage.value = 'Your results are ready! Check your email.'
  })
}

onUnmounted(() => {
  if (socket.value) {
    socket.value.disconnect()
  }
})
</script>

<style scoped>
.wizard {
  max-width: 600px;
  margin: 0 auto;
}

.steps {
  display: flex;
  justify-content: space-between;
  margin-bottom: 30px;
}

.steps span {
  padding: 10px 20px;
  background: #eee;
  border-radius: 4px;
}

.steps span.active {
  background: #007bff;
  color: white;
}

.steps span.completed {
  background: #28a745;
  color: white;
}

.step-content {
  padding: 20px;
  border: 1px solid #ddd;
  border-radius: 8px;
}

.preview {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin: 20px 0;
}

.preview-item img {
  width: 100px;
  height: 100px;
  object-fit: cover;
}

textarea, input[type="email"] {
  width: 100%;
  padding: 10px;
  margin: 10px 0;
}

textarea {
  min-height: 100px;
}

button {
  padding: 10px 20px;
  background: #007bff;
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
}

button:disabled {
  background: #ccc;
}

.status-update {
  margin-top: 20px;
  padding: 15px;
  background: #f0f8ff;
  border-radius: 4px;
}
</style>
```

### 4.4 Create frontend/user/vue/src/stores/submission.js

```javascript
import { defineStore } from 'pinia'
import axios from 'axios'

export const useSubmissionStore = defineStore('submission', {
  state: () => ({
    submissionId: null,
    status: null,
    error: null,
    loading: false
  }),

  actions: {
    async submit(data) {
      this.loading = true
      this.error = null

      try {
        const response = await axios.post('/api/user/submit', data)

        // Expecting 202 Accepted
        if (response.status === 202) {
          this.submissionId = response.data.submission_id
          this.status = 'submitted'
          return response.data
        }
      } catch (error) {
        this.error = error.response?.data?.message || error.message
        throw error
      } finally {
        this.loading = false
      }
    },

    async getStatus(submissionId) {
      try {
        const response = await axios.get(`/api/user/status/${submissionId}`)
        this.status = response.data.status
        return response.data
      } catch (error) {
        this.error = error.message
        throw error
      }
    }
  }
})
```

### 4.5 Create frontend/admin/vue/package.json

```json
{
  "name": "vbwd-admin",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "test": "vitest",
    "lint": "eslint . --ext .vue,.js,.jsx,.cjs,.mjs --fix"
  },
  "dependencies": {
    "vue": "^3.4.0",
    "vue-router": "^4.2.5",
    "pinia": "^2.1.7",
    "axios": "^1.6.2"
  },
  "devDependencies": {
    "@vitejs/plugin-vue": "^4.5.2",
    "vite": "^5.0.8",
    "vitest": "^1.1.0",
    "eslint": "^8.56.0",
    "eslint-plugin-vue": "^9.19.2"
  }
}
```

### 4.6 Create frontend/admin/vue/src/views/SubmissionsList.vue

```vue
<template>
  <div class="submissions">
    <h1>Submissions</h1>

    <div class="filters">
      <select v-model="statusFilter" @change="loadSubmissions">
        <option value="">All Statuses</option>
        <option value="pending">Pending</option>
        <option value="processing">Processing</option>
        <option value="completed">Completed</option>
        <option value="failed">Failed</option>
      </select>
    </div>

    <table>
      <thead>
        <tr>
          <th>ID</th>
          <th>Email</th>
          <th>Status</th>
          <th>Created</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="submission in submissions" :key="submission.id">
          <td>{{ submission.id }}</td>
          <td>{{ submission.email }}</td>
          <td>
            <span :class="'status-' + submission.status">
              {{ submission.status }}
            </span>
          </td>
          <td>{{ formatDate(submission.created_at) }}</td>
          <td>
            <router-link :to="`/submissions/${submission.id}`">
              View
            </router-link>
          </td>
        </tr>
      </tbody>
    </table>

    <div class="pagination">
      <button @click="prevPage" :disabled="page === 1">Previous</button>
      <span>Page {{ page }} of {{ totalPages }}</span>
      <button @click="nextPage" :disabled="page === totalPages">Next</button>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, computed } from 'vue'
import axios from 'axios'

const submissions = ref([])
const page = ref(1)
const perPage = ref(20)
const total = ref(0)
const statusFilter = ref('')

const totalPages = computed(() => Math.ceil(total.value / perPage.value))

async function loadSubmissions() {
  const params = { page: page.value, per_page: perPage.value }
  if (statusFilter.value) {
    params.status = statusFilter.value
  }

  const response = await axios.get('/api/admin/submissions', { params })
  submissions.value = response.data.data
  total.value = response.data.pagination.total
}

function formatDate(dateStr) {
  return new Date(dateStr).toLocaleString()
}

function nextPage() {
  if (page.value < totalPages.value) {
    page.value++
    loadSubmissions()
  }
}

function prevPage() {
  if (page.value > 1) {
    page.value--
    loadSubmissions()
  }
}

onMounted(() => {
  loadSubmissions()
})
</script>

<style scoped>
table {
  width: 100%;
  border-collapse: collapse;
}

th, td {
  padding: 12px;
  text-align: left;
  border-bottom: 1px solid #ddd;
}

.status-pending { color: #ffc107; }
.status-processing { color: #17a2b8; }
.status-completed { color: #28a745; }
.status-failed { color: #dc3545; }

.pagination {
  margin-top: 20px;
  display: flex;
  justify-content: center;
  gap: 20px;
  align-items: center;
}
</style>
```

---

## Directory Structure After Completion

```
frontend/
├── admin/
│   └── vue/
│       ├── package.json
│       ├── vite.config.js
│       ├── index.html
│       └── src/
│           ├── App.vue
│           ├── main.js
│           ├── router/
│           │   └── index.js
│           ├── stores/
│           │   └── auth.js
│           └── views/
│               ├── Login.vue
│               ├── Dashboard.vue
│               └── SubmissionsList.vue
└── user/
    └── vue/
        ├── package.json
        ├── vite.config.js
        ├── index.html
        └── src/
            ├── App.vue
            ├── main.js
            ├── router/
            │   └── index.js
            ├── stores/
            │   └── submission.js
            └── views/
                └── SubmissionWizard.vue
```

---

## Acceptance Criteria

- [ ] User app: 3-step wizard works correctly
- [ ] User app: WebSocket receives status updates
- [ ] Admin app: Lists submissions with pagination
- [ ] Admin app: Filters by status
- [ ] Both apps build successfully for production

---

## Dependencies

- Task 01 (docker-compose.yaml)
- Task 02 (container configs)
- Task 03 (Python API)

---

## Next Task

- `05-testing.md`
