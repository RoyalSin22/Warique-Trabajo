// backend/src/menu/menu.module.ts
import { Module } from '@nestjs/common';
import { CategoriesController } from './categories.controller';
import { CategoriesService } from './categories.service';
import { DishesController } from './dishes.controller';
import { DishesService } from './dishes.service';

@Module({
  controllers: [CategoriesController, DishesController],
  providers: [CategoriesService, DishesService],
  exports: [DishesService],
})
export class MenuModule {}
