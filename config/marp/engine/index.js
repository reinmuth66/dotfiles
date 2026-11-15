// marp のエンジンの拡張。.marprc.yml の engine がこのファイルを指す。
// 記法の説明は config/marp/README.md にある。
const container = require("./container.js");
const diagram = require("./diagram.js");
const section = require("./section.js");

module.exports = ({ marp }) => marp.use(container).use(diagram).use(section);
