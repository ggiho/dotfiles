-- 브라우저 실시간 마크다운 프리뷰 (스크롤 동기화, mermaid/latex/이미지 등
-- render-markdown.nvim으로 부족한 "프로덕션 실제 모양" 확인용).
return {
	"iamcco/markdown-preview.nvim",
	cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
	ft = { "markdown" },
	build = function()
		vim.fn["mkdp#util#install"]() -- 프리뷰 서버 바이너리 자동 설치 (node 빌드 불필요)
	end,
	keys = {
		{ "<leader>mp", "<cmd>MarkdownPreviewToggle<cr>", ft = "markdown", desc = "Markdown 브라우저 프리뷰 토글" },
	},
	init = function()
		vim.g.mkdp_auto_close = 1 -- 버퍼 벗어나면 프리뷰 탭 자동 닫기
	end,
}
