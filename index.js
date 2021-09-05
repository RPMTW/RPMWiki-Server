const express = require('express');
const cors = require('cors');
const app = express();
const { Sequelize } = require('sequelize');
const router = require('./routes');
const authRouter = require('./routes/auth');
const { RateLimiterMemory } = require('rate-limiter-flexible');
require('dotenv').config();

const rateLimiter = new RateLimiterMemory({ points: 3, duration: 1, blockDuration: 60 });

const sequelize = new Sequelize({
    host: process.env['dataBaseHost'],
    port: process.env['dataBasePort'],
    username: 'postgres',
    password: process.env['dataBasePassword'],
    database: 'data',
    dialect: 'postgres',
    logging: (...msg) => {
        //紀錄SQL日誌
        console.log(msg);
    },
});

run();

async function run() {
    try {
        await sequelize.authenticate();
        console.log('連接資料庫成功');
    } catch (error) {
        console.error('連接資料庫失敗：', error);
    }

    try {
        var init = function (req, res, next) {
            rateLimiter.consume(req.ip).then(() => {
                console.log(`new user: ${req.ip}`)
                next();
            }).catch(() => {
                return res.json({
                    message: 'Too Many Requests',
                }).status(429);
            });
        };

        app.use(cors()).use(init)
            .use("/", router)
            .use("/auth", authRouter(sequelize))
            .use(init)
            .use(function (req, res, next) {
                res.json({
                    message: "Not Found"
                }).status(404);
            }).use(function (err, req, res, next) {
                console.error(err);
                res.json({
                    message: "Internal Server Error"
                }).status(500);
            });;

        app.listen(3000, () => {
            console.log('RPMWiki Server Started');
        });

    } catch (error) {
        console.error('API發生未知錯誤:', error);
    }


}

exports.sequelize = sequelize;