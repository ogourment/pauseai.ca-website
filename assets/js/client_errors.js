export function watchConnection(socket) {
  let timer
  socket.onClose(() => {
    if (!timer) timer = setTimeout(() => {
      timer = undefined
      if (navigator.onLine && !document.hidden && !socket.isConnected()) window.dispatchEvent(new Event("pauseai:connection-failed"))
    }, 60000)
  })
  socket.onOpen(() => { clearTimeout(timer); timer = undefined })
}
