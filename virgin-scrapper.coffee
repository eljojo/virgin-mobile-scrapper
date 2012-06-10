http = require("http")
jsdom = require("jsdom")
async = require("async")

malo = ""

concurrency = 4
exports.set_concurrency = (new_concurrency) -> concurrency = new_concurrency

cookies = ''
post_data = ''
options =
  host: "www.virginmobile.cl"
  port: 80
  path: "/"
  method: "GET"
  headers:
    "User-Agent": "iPhone iOS Mobile"

do_debug = false
cl = (what) -> console.log what
debug = (what) -> cl what if do_debug

trim = (str) ->
	str = str.replace(/^\s\s*/, '')
	ws = /\s/
	i = str.length
	i while ws.test(str.charAt(--i))
	return str.slice(0, i + 1);

get_html = (path, callback) ->
  options.path = path
  debug " >> requesting #{options.host} #{options.path}"
  options.headers.cookie = cookies
  if post_data.length > 0
    options.headers['Content-Length'] = post_data.length
    options.method = 'POST'
  else
    options.headers['Content-Length'] = 0
    options.method = 'GET'
  req = http.request(options, (res) ->
    res.setEncoding "utf8"
    data = ""
    res.on "data", (chunk) -> data += chunk
    res.on "end", -> callback data, res.headers
  )
  req.on "error", (e) -> console.log "problem with request: " + e.message
  if post_data
    req.write post_data
    post_data = ''
  req.end()

parse = (html, procesar) ->
  jsdom.env html, [ "jquery-1.7.1.min.js" ], (errors, window) ->
    procesar window.$
    setTimeout (->
      window.__stopAllTimers()
      window.close()
    ), 3000

extract_cookies = (raw_cookies) ->
  raw_cookies = raw_cookies.join ";"
  r = ''
  raw_cookies.split(';').map (cookie) ->
    cookie = trim cookie
    return if cookie.length == 0
    par = cookie.split('=')[0]
    r += cookie + '; ' unless par == 'path' or par == 'expires' or par == 'HttpOnly'
  r

login = (user_data, callback) ->
  post_data = "user_session[email]=#{user_data['email']}&user_session[password]=#{user_data['password']}&remember_me=&commit=Ingresar"
  debug "logging in #{user_data['email']} @ virginmobile.cl"
  get_html '/session/create', (html, headers) ->
    debug 'logged in @ virginmobile.cl, requesting mi.virginmobile.cl'
    cookies = extract_cookies headers['set-cookie']
    options.host = 'mi.virginmobile.cl'
    get_html '/me', (html, headers) ->
      debug 'getting oauth request from mi.virginmobile.cl, authorizing @ virginmobile.cl'
      options.host = 'www.virginmobile.cl'
      cookies += extract_cookies headers['set-cookie']
      url = headers['location'].replace('http://www.virginmobile.cl', '')
      get_html url, (html, headers) ->
        debug 'oauth key authorized, logging in with oauth authorization @ mi.virginmobile.cl'
        url = headers['location'].replace('https://mi.virginmobile.cl', '')
        options.host = 'mi.virginmobile.cl'
        get_html url, (html, headers) -> 
          debug 'logged in!'
          cookies = extract_cookies headers['set-cookie']
          callback()

get_resume_info = (text) ->
  return 'sms' if text.indexOf('SMS') > -1
  return 'web' if text.indexOf('Web') > -1
  return 'minutos'

process_data = (html, callback) ->
  parse html, ($) ->
    data = 
      numero: $("#current_subscriber option[selected=selected]").text()
      info: {}
      credit: {}
      antiplan: {}
      gancho: $("div.alert.alert-info").last().text().split(' ')[2]
    $credit = $("div.well.credit")
    data.credit["normal"] = parseInt trim $credit.first().find("span").text().substring(1)
    data.credit["promotional"] = parseInt trim $credit.last().find("span").text().substring(1) if $credit.last().length > 0
    antiplan = $("div.well").not(".credit").first().text().split("\n")
    if antiplan.length == 7 and trim(antiplan[5]) == 'Desactivar' #tenemos antiplan. 
      data.antiplan =
        plan: antiplan[1].trim()
        renewal: antiplan[3].trim()
    $("div.well.resume").each ->
      type = get_resume_info $(this).find('h2').text()
      # columns = $(this).find("thead tr").text().trim().split('  ').join('').split('\n')
      content = []
      $(this).find('tbody tr').each ->
        $rows = $(this).find("td")
        row =
          total: $rows.eq(0).text().trim().split(' ')[0]
          left: $rows.eq(1).text().trim().split(' ')[0]
          expire: $rows.eq(2).text().trim()
        content.push row
      data.info[type] = content
    callback data

exports.getData = (user_data, callback) -> login user_data, -> get_html '/me', (html, headers) -> process_data html, callback