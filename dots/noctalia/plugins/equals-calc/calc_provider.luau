-- Equals Calculator — arithmetic straight from the launcher input.
--
-- Two ways in, both the ones iNiR's search offers:
--   "=2+2"      the leading "=" says "this is a sum", whatever follows it
--   "2+2"       an expression that starts with a number and carries an operator
--
-- The "=" has to be stripped here rather than handed to qalc, which reads it as
-- an equality test and answers 0. Everything else is passed through untouched,
-- so units and currencies ("10 km to m", "100 usd to eur") work as well.

local PREFIX = "="

local function trim(s)
	return noctalia.string.trim(tostring(s or ""))
end

local function shellQuote(s)
	return "'" .. s:gsub("'", "'\"'\"'") .. "'"
end

-- qalc answers *everything* — "hello" comes back as "2.718281828 B·h·L²" — so an
-- unprefixed query only counts as arithmetic when it both starts like a number
-- and reads like a calculation. An explicit "=" skips this test entirely: the
-- user already said what they meant.
local function looksLikeMath(expr)
	if not expr:match("^[%d%(%.]") then
		return false
	end
	return expr:match("[%+%-%*/%^%%!]") ~= nil
		or expr:match("%f[%a]to%f[%A]") ~= nil
		or expr:match("^%s*0[xb]%x") ~= nil
end

-- The expression to evaluate, or nil when this query is not ours. The score
-- rides along: the global search merges every provider's rows into one list and
-- orders them by it, and an answer the user asked for with "=" has to outrank
-- the "Run: =2+2" the shell provider offers for the same text — otherwise Enter
-- throws the sum at a terminal.
local function expressionOf(query)
	if query:sub(1, #PREFIX) == PREFIX then
		local expr = trim(query:sub(#PREFIX + 1))
		if expr == "" then
			return nil
		end
		return expr, 1000
	end
	-- Reached either unprefixed from the global search or behind "/eq", where
	-- the prefix is already stripped; the same shape test covers both. No "="
	-- was typed, so this is a guess about intent — it leads, but not as firmly.
	if looksLikeMath(query) then
		return query, 500
	end
	return nil
end

local pendingQuery = nil
-- The answer behind the result row. The row keeps one stable id ("copy") across
-- the whole life of a query — see onQuery — so the value cannot travel in the
-- id the way it usually would.
local lastAnswer = nil

-- One row, always the same id, drawn before qalc has answered. Observed: build
-- the row only once the answer is in (a later id, a later render) and the
-- keyboard selection sits on the shell provider's "Run: =2+2" instead, which
-- runs the sum in a terminal on Enter. Row order alone does not fix it — the
-- answer row sorts first and is still not the selected one.
local function resultRow(title, subtitle, glyph, score)
	return {
		id = "copy",
		title = title,
		subtitle = subtitle,
		glyph = glyph,
		score = score,
	}
end

function onQuery(query)
	query = trim(query)
	pendingQuery = query

	local expr, score = expressionOf(query)
	if expr == nil then
		lastAnswer = nil
		launcher.setResults(query, {})
		return
	end

	-- Draw the row before qalc has said anything: it has to exist by the time
	-- the other providers' rows land, or the selection settles on one of theirs.
	lastAnswer = nil
	launcher.setResults(query, { resultRow(noctalia.tr("pending_title"), expr, "calculator", score) })

	noctalia.runAsync("qalc -t -- " .. shellQuote(expr), function(result)
		if pendingQuery ~= query then
			return -- a newer keystroke already superseded this one
		end
		local answer = trim(result.stdout)
		if answer == "" then
			-- qalc writes parse failures to stderr and prints nothing.
			local err = trim(result.stderr)
			lastAnswer = nil
			launcher.setResults(query, {
				resultRow(err ~= "" and err or noctalia.tr("error_subtitle"), expr, "calculator-off", score),
			})
			return
		end
		lastAnswer = answer
		launcher.setResults(query, {
			resultRow(noctalia.tr("result_title", { result = answer }), expr, "calculator", score),
		})
	end)
end

-- Enter pressed in the moment between the row appearing and qalc answering does
-- nothing: there is no answer to copy yet. qalc's first call in a session can
-- take a beat (it loads its exchange rates), so the gap is real, if small.
function onActivate(id)
	if id == "copy" and lastAnswer ~= nil then
		noctalia.copyToClipboard(lastAnswer)
	end
end
