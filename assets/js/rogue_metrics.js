import {learningId} from "./learning_id"
// One aggregate per attempt, never a stream of pointer movements or personal data.
export function rogueMetrics(root) {
  let state, stage = 0, timer
  const fresh = () => ({id: learningId(), sequence: 0, furthest_stage: 0, completed: false, buttons: {}, locale:root.dataset.locale})
  try {state=JSON.parse(sessionStorage.getItem('pauseai-ca:rogue-attempt')||'null')} catch (_) {}
  if (!state || !state.id) state=fresh()
  function flush() {
    clearTimeout(timer)
    try {sessionStorage.setItem('pauseai-ca:rogue-attempt',JSON.stringify(state))} catch (_) {}
    fetch('/learning/game-progress',{method:'POST',keepalive:true,headers:{'content-type':'application/json','x-csrf-token':document.querySelector('meta[name=csrf-token]').content},body:JSON.stringify(state)}).catch(()=>{})
  }
  function record(event, values={}) {
    if (event==='game_ended') state.completed=values.reason==='finale'
    if (event==='button_clicked') {
      const key=`${stage}:${values.button_id}`
      state.buttons[key]=Math.min(10000,(state.buttons[key]||0)+1)
    }
    if (['source_opened','learning_path_opened','resource_bookmark_changed'].includes(event)) {
      const key=`${stage}:${event}`;state.buttons[key]=Math.min(10000,(state.buttons[key]||0)+1)
    }
    if (!['button_clicked','game_ended','game_stage_view','source_opened','learning_path_opened','resource_bookmark_changed'].includes(event)) return
    state.sequence++
    clearTimeout(timer);timer=setTimeout(flush,200)
    // The consenting parent owns gtag. Never pass attempt, visitor or account IDs.
    const target=window.gtag?window:window.opener
    try {if(localStorage.getItem('pauseai-ca:analytics-consent')==='granted' && target?.gtag && ['game_stage_view','game_ended','learning_path_opened','button_clicked'].includes(event)) target.gtag('event',event,{game:'rogue_popup',stage,button:values.button_id,completed:state.completed,page_location:location.origin+location.pathname,page_referrer:location.origin})} catch (_) {}
  }
  document.addEventListener('click',event=>{const button=event.target.closest('button');if(button&&root.contains(button))record('button_clicked',{button_id:button.id||button.dataset.metric||'choice'})},true)
  window.addEventListener('pagehide',flush)
  return {begin(){},newAttempt(){state=fresh()},record,stage(value){stage=value;state.furthest_stage=Math.max(value,state.furthest_stage);record('game_stage_view')},endStage(){flush()}}
}
