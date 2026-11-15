// marp のエンジンの拡張。.marprc.yml の engine がこのファイルを指す。
// 記法の説明は config/marp/README.md にある。
const container = require("./container.js");

module.exports = ({ marp }) => marp.use(container);
