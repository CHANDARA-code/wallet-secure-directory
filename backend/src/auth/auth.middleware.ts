import { Inject, Injectable, NestMiddleware } from '@nestjs/common';
import { toNodeHandler } from 'better-auth/node';
import type { NextFunction, Request, Response } from 'express';
import { AUTH } from './auth.constants.js';
import type { Auth } from './auth.factory.js';

const MAX_AUTH_BODY_BYTES = 100 * 1024;

@Injectable()
export class AuthMiddleware implements NestMiddleware {
  private readonly handler: ReturnType<typeof toNodeHandler>;

  constructor(@Inject(AUTH) auth: Auth) {
    this.handler = toNodeHandler(auth);
  }

  use(req: Request, res: Response, next: NextFunction) {
    const contentLength = req.headers['content-length'];
    if (contentLength) {
      const parsedLength = Number(contentLength);
      if (Number.isFinite(parsedLength) && parsedLength > MAX_AUTH_BODY_BYTES) {
        res.setHeader('Connection', 'close');
        res.status(413).json({
          statusCode: 413,
          message: 'Payload Too Large',
          error: 'Payload Too Large',
        });
        return;
      }
    }

    if (req.method !== 'GET' && req.method !== 'HEAD') {
      let receivedBytes = 0;
      const onData = (chunk: Buffer | string) => {
        receivedBytes +=
          typeof chunk === 'string' ? Buffer.byteLength(chunk) : chunk.length;
        if (receivedBytes > MAX_AUTH_BODY_BYTES) {
          req.off('data', onData);
          req.pause();
          if (!res.headersSent) {
            res.setHeader('Connection', 'close');
            res.status(413).json({
              statusCode: 413,
              message: 'Payload Too Large',
              error: 'Payload Too Large',
            });
            const cleanup = () => {
              if (!req.destroyed) {
                req.destroy();
              }
            };
            res.once('finish', cleanup);
            res.once('close', cleanup);
          }
        }
      };
      req.on('data', onData);
    }

    this.handler(req, res).catch((err) => {
      if (!res.headersSent) {
        next(err);
      }
    });
  }
}
