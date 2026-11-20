defmodule PauseAiCaWeb.ClientErrorController do
  use PauseAiCaWeb, :controller

  def create(conn, params) do
    # Fixed buckets bound memory. Collisions can only reduce the intake allowance.
    bucket = :erlang.phash2(conn.remote_ip, 256)
    minute = div(System.system_time(:second), 60)
    key = {rem(minute, 2), bucket}
    :ets.select_delete(:pauseai_browser_rate, [{{key, :"$1", :_}, [{:<, :"$1", minute}], [true]}])

    if :ets.update_counter(:pauseai_browser_rate, key, {3, 1}, {key, minute, 0}) <= 20 do
      PauseAiCa.Incidents.browser(params)
    end

    send_resp(conn, 204, "")
  end
end
