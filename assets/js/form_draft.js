// Per-tab drafts for ordinary form fields. Credentials, capabilities and uploads
// are excluded. The consumer owns restoration and validation through its event.
export const FormDraft = {
  mounted() {
    this.key = this.el.dataset.draftKey
    this.prefix = this.el.dataset.draftPrefix + '['
    this.submitted = this.el.dataset.submitted === 'true'
    this.saveDraft = () => {
      const values = this.readDraft()
      if (this.el.querySelector("[data-experience]") || values.experience) values.experience = {}
      this.el.querySelectorAll('input,textarea,select').forEach(field => {
        if (!field.name.startsWith(this.prefix) || ['hidden','password','file'].includes(field.type) || field.readOnly) return
        if (field.dataset.experience) {
          if (field.checked && field.value) values.experience[field.dataset.experience] = field.value
          return
        }
        const name = field.name.slice(this.prefix.length, -1)
        if (field.name.endsWith('][]') && field.type === 'checkbox') {
          const key = field.name.slice(this.prefix.length, -3)
          const group = Array.from(this.el.elements).filter(input => input.name === field.name && input.type === 'checkbox')
          values[key] = group.filter(input => input.checked).map(input => input.value)
          return
        }
        values[name] = field.type === 'checkbox' ? String(field.checked) : field.value
      })
      if (this.el.hasAttribute('data-interest-group')) values.interest_group = this.el.dataset.interestGroup
      try { sessionStorage.setItem(this.key, JSON.stringify({at: Date.now(), values})) } catch (_) {}
    }
    this.el.addEventListener('input', this.saveDraft)
    this.el.addEventListener('change', this.saveDraft)
    const values = this.readDraft()
    if (Object.keys(values).length) this.pushEventTo(this.el, 'restore-draft', {values})
  },
  updated() {
    const interestGroup = this.el.hasAttribute('data-interest-group')
    if (!interestGroup && !this.el.hasAttribute('data-draft-clear-on-save')) return
    const submitted = this.el.dataset.submitted === 'true'
    if (submitted && (interestGroup || !this.submitted)) {
      try { sessionStorage.removeItem(this.key) } catch (_) {}
    } else if (interestGroup && !submitted) {
      this.saveDraft()
    }
    this.submitted = submitted
  },
  readDraft() {
    try {
      const data = JSON.parse(sessionStorage.getItem(this.key) || 'null')
      return data && Date.now() - data.at < 2 * 60 * 60 * 1000 ? data.values : {}
    } catch (_) { return {} }
  },
  destroyed() {
    this.el.removeEventListener('input', this.saveDraft)
    this.el.removeEventListener('change', this.saveDraft)
  }
}
