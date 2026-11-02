# 账号头像区域精简 · 2026-10-30

按用户反馈删除头像区域内“一键登录 ›”“账号信息 ›”等重复提示。未登录保留头像、“登录华为账号”和一行必要说明；已登录保留头像、昵称和登录状态。整块身份区域作为入口，不另增解释性文案。手机卡片104→96vp，下方内容相应收拢。宽屏D01移除重复登录按钮，左侧列表上移56vp；D02/D10移除账号信息文字。

修改手机H01/H02/H03/H04/H07、宽屏D01/D02/D10，浅深共16个页面源SVG；重组light/dark下account-cloud.svg和wide/combined.svg两个画板，共4个组合SVG。浏览器预览和截图为account-header-review.html、account-header-browser.png、account-header-wide-browser.png。生成脚本scripts/simplify-account-header.py，变更与验证见account-header-*.json。原稿备份在before-account-header-simplify中，Figma修订前两个画板保留并移至右侧。

验证：16个变体头像卡片内均无重复提示；手机卡片保持两条身份文本、96vp高度与整卡入口标注；WebDAV“检查账号信息后重试”保留；H07独立的授权取消后重试主操作保留。浏览器已检查手机未登录、已登录和宽屏；Figma检查对应页面并确认保存。原生业务逻辑未修改，未运行鸿蒙构建；点击行为仍为设计约定。

初始圆角/间距验证记录是上一轮基线，随后发生的文案/留白变化以本修订与account-header-verification.json为准。若重建设计，先执行build-layout-tokens.py，再执行simplify-account-header.py；不可仅重建基线而恢复已经删除的提示。

同步过程中，旧图层名称过长导致行定位失败，误触锁定后已撤销；改为精确选中画板再同步。未覆盖其他稿件。

手机画板首次导入后跳转过早未保留，已重新导入并检查新稿。当前页面直达：

- [H01 我的小巧 · 未登录](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/%E5%B0%8F%E5%B7%A7%E8%AE%B0%E8%B4%A6%EF%BD%9CUI-%E8%A1%A5%E5%85%A8-%C2%B7-%E9%B8%BF%E8%92%99?node-id=124-8&t=oEQGQd6LcelEdJWZ-0)
- [H02 我的小巧](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH?node-id=124-139)
