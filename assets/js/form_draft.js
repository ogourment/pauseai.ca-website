// Per-tab drafts for ordinary form fields. Credentials, capabilities and uploads
// are excluded. The consumer owns restoration and validation through its event.
export const FormDraft = {
  mounted() {
    this.key = this.el.dataset.draftKey
    this.prefix = this.el.dataset.draftPrefix + '['
    this.saveDraft = () => {
      const values = this.readDraft()
      this.el.querySelectorAll('input,textarea,select').forEach(field => {
        if (!field.name.startsWith(this.prefix) || ['hidden','password','file'].includes(field.type) || field.readOnly) return
        const name = field.name.slice(this.prefix.length, -1)
        values[name] = field.type === 'checkbox' ? String(field.checked) : field.value
      })
      try { sessionStorage.setItem(this.key, JSON.stringify({at: Date.now(), values})) } catch (_) {}
    }
    this.el.addEventListener('input', this.saveDraft)
    this.el.addEventListener('change', this.saveDraft)
    const values = this.readDraft()
    if (Object.keys(values).length) this.pushEventTo(this.el, 'restore-draft', {values})
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
