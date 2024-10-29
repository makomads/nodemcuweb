print("NodeMCU Web Server")

wifi.setmode(wifi.STATIONAP) 
wifi.setphymode(wifi.PHYMODE_N)         --802.11n

--グローバル変数
CONFIGFILE="config.txt"
STA_CFG={}
AP_CFG={}
AP_IP_CFG={}
AP_DHCP_CFG ={}

--グローバル変数デフォルト値設定

--接続先ルーターデフォルト値設定
STA_CFG.ssid="Buffalo-G-ABCD"
STA_CFG.pwd="abcdef1234567"
STA_CFG.save=false      --独自のファイルに保存するのでライブラリの保存機能は使わない

--APモードデフォルト値設定
AP_CFG.ssid="esp8266"   --- SSID: 1-32 chars
AP_CFG.pwd="wifipassword"       --- Password: 8-64 chars. Minimum 8 Chars
AP_CFG.auth=AUTH_OPEN   --- Authentication: AUTH_OPEN, AUTH_WPA_PSK, AUTH_WPA2_PSK, AUTH_WPA_WPA2_PSK
AP_CFG.channel = 6      --- Channel: Range 1-14
AP_CFG.hidden = 0       --- Hidden Network? True: 1, False: 0
AP_CFG.max=4            --- Max Connections: Range 1-4
AP_CFG.beacon=100       --- WiFi Beacon: Range 100-60000
AP_IP_CFG.ip="192.168.66.1"
AP_IP_CFG.netmask="255.255.255.0"
AP_IP_CFG.gateway="192.168.66.1"
AP_DHCP_CFG.start = "192.168.66.2"

--設定読み込み
if file.exists(CONFIGFILE) then
  file.open(CONFIGFILE,"r")
  while true do
    line = file.readline()
    if line == nil then break end
    k,v = string.match(line,"([^=]+)=([^\n]*)")
    if k=="STA_CFG.ssid" then STA_CFG.ssid = v
    elseif k=="STA_CFG.pwd" then STA_CFG.pwd = v
    elseif k=="AP_CFG.ssid" then AP_CFG.ssid = v
    elseif k=="AP_CFG.pwd" then  AP_CFG.pwd = v
    end
  end
  file.close()
end

--WiFi接続
wifi.sta.config(STA_CFG)
wifi.ap.config(AP_CFG)
wifi.ap.setip(AP_IP_CFG)
wifi.ap.dhcp.config(AP_DHCP_CFG)
wifi.ap.dhcp.start()

--ページ処理関数定義
--これらの関数はURLパラメータを引数に取り、テンプレート内で使われる変数を返す

--インデックスページ
function indexpage(urlparams)
  return {}
end

--設定ページ
function configpage(urlparams)
  --URLパラメータ指定なしの場合は現在の設定情報を返す
  if urlparams == nil or urlparams["stssid"] == nil then
    return {stssid=STA_CFG.ssid, stpass=STA_CFG.pwd, apssid=AP_CFG.ssid, appass=AP_CFG.pwd, 
      msg=""}
  end
  --URLパラメータがあれば、設定を更新(適用には再起動の必要がある)
  STA_CFG.ssid = urlparams["stssid"]
  STA_CFG.pwd = urlparams["stpass"] 
  AP_CFG.ssid = urlparams["apssid"]
  AP_CFG.pwd = urlparams["appass"]
  file.open(CONFIGFILE,"w")
  file.writeline("STA_CFG.ssid=" .. STA_CFG.ssid)
  file.writeline("STA_CFG.pwd=" .. STA_CFG.pwd)
  file.writeline("AP_CFG.ssid=" .. AP_CFG.ssid)
  file.writeline("AP_CFG.pwd=" .. AP_CFG.pwd)  
  file.close()
  
  return {stssid=STA_CFG.ssid, stpass=STA_CFG.pwd, apssid=AP_CFG.ssid, appass=AP_CFG.pwd, 
      msg="設定を更新しました。再起動してください。"}
end

--再起動ページ
function restartpage(urlparams)
  local tmr_restart = tmr.create()
  tmr_restart:register(4000, tmr.ALARM_SINGLE, node.restart)
  tmr_restart:start()
  return {}
end

--モニタページ
function monitorpage(urlparams)
  local tplvars = {}
  tplvars["heapval"] = node.heap()
  tplvars["adc0val"] = adc.read(0)
  tplvars["staip"] = wifi.sta.getip()
  if tplvars["staip"] == nil then tplvars["staip"] = "0.0.0.0" end
  tplvars["apip"] = wifi.ap.getip()

  return tplvars
end

--パスと処理関数の対応テーブル
--テンプレートファイルはパスに.htmlをつけたものが使われる
--例えば /configが指定されたら、configpage()が処理され、テンプレートにconfig.htmlが使用される
routetbl = {index=indexpage, config=configpage, restart=restartpage, monitor=monitorpage}

-- create a TCP server
if svr~=nil then
  svr:close()
end
svr = net.createServer(net.TCP) 

--ポート80で待ち受け
svr:listen(80, function(conn)
  conn:on("receive", function(conn, request)
    -- HTTP requestをパース(例"GET /index.html HTTP/1.1")
    --パラメータ付きでパースして失敗したらパラメータなしでパースする
    local _, _, method, path, param = string.find(request, "([A-Z]+) (.+)?(.+) HTTP")
    if method == nil then
      _, _, method, path = string.find(request, "([A-Z]+) (.+) HTTP")
    end
    
    --URLパラメータを連想配列に変換
    --NodeMCUにはstring.split()が実装されてない
    urlparams = {}
    if param ~= nil then
      for k, v in string.gmatch(param, "(%w+)=([%w-_]+)") do
        urlparams[k] = v
      end
    end
    
    --リクエスト処理
    if method == "GET" then
      path = string.gsub(path, "/", "")
      if path == "" then
        path = "index"
      end
      
      --パスがルーティングテーブルにあればルーティング処理しテンプレートを使用
      routefunc = nil
      for key, val in pairs (routetbl) do
        if key==path then routefunc=val end
      end
      if routefunc ~= nil then
        tplvars = routefunc(urlparams)
        path = path .. ".html"
      else
        tplvars = {}
      end
      
      --ファイルを開いて送信
      if file.exists(path) then
        file.open(path,"r")
        resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n" 
        conn:send(resp)
        while true do
          --メモリ節約のためファイル全体をバッファリングせず1行ずつ処理する
          line = file.readline()
          if line == nil then break end
          --テンプレートの変数を置換する
          for key, val in pairs(tplvars) do
            if val==nil then val="nil" end
            line = string.gsub(line, "{{"..key.."}}", val)
          end
          conn:send(line)
        end
        file.close()
      else
        --ファイルがなかった場合
        resp = "HTTP/1.1 404 Not Found\r\nContent-Type: text/html\r\n\r\n" ..
               "<html><body><h1>404 Not Found</h1></body></html>"
        conn:send(resp)
      end
    else
      --GET以外のメソッドを指定された場合
      resp = "HTTP/1.1 405 Method Not Allowed\r\nContent-Type: text/html\r\n\r\n" ..
              "<html><body><h1>405 Method Not Allowed</h1></body></html>"
      conn:send(resp)
    end
  end)
  
  -- close the connection after sending
  conn:on("sent", function(conn)
    conn:close()
  end) 
end)




